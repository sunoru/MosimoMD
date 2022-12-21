function default_callback(setup::MDSetup, logging_period=min(1000, setup.data_steps / 10))
    model = setup.model
    (state::MDState; force_logging = false) -> begin
        @match state.stage begin
            StageBegin => println(" Step |   Time   |  Potential  |   Kinetic   |    Total")
        end
        s = system(state)
        kinetic = kinetic_energy(s, model)
        potential = potential_energy(s, model)
        total = potential + kinetic
        @printf "%5d |%9.5f |%13.6e|%13.6e|%13.6e" state.step state.time potential kinetic total
    end
end

function evolve!(state::MDState)
    _, δt = move!(state.integrator)
    s = system(state)
    if has_pbc(s)
        update_periods!(s)
    end
    state.time += δt
    state
end

function _run_until(f, state, target, step=0)
    while step < target
        step += 1
        f(state, step)
        evolve!(state)
    end
end

function run_stage(::typeof(StageBegin), state, callback)
    @info "MD started."
    state.stage = StageInitial(0)
    state
end
function run_stage(stage::StageInitial, state, callback)
    initial_steps = state.setup.initial_steps
    @info "Initial $initial_steps steps..."
    _run_until(state, initial_steps, stage.step) do state, step
        state.stage = StageInitial(step)
        callback(state)
    end
    state.stage = StageCooling(0)
    state
end
function run_stage(stage::StageCooling, state, callback)
    setup = state.setup
    cooling_steps = setup.cooling_steps
    temp_control_period = setup.temp_control_period
    model = setup.model
    compressed_temperature = setup.compressed_temperature
    @info "Cooling for $cooling_steps steps..."
    _run_until(state, cooling_steps, stage.step) do state, step
        state.stage = StageCooling(step)
        callback(state)
        if step % temp_control_period == 1
            rescale_temperature!(
                system(state),
                model,
                compressed_temperature
            )
        end
        state
    end
    state.stage = StageRescalingTemperature(0, 1)
    state
end
function run_stage(stage::StageRescalingTemperature, state, callback)
    it = stage.iteration
    setup = state.setup
    temp_control_steps = setup.temp_control_steps
    temp_control_period = setup.temp_control_period
    temperature = setup.temperature
    model = setup.model
    @info "[$it/$(state.setup.relax_iterations)] Rescaling temperature for $temp_control_steps steps..."
    _run_until(state, temp_control_steps, stage.step) do state, step
        state.stage = StageRescalingTemperature(step, it)
        callback(state)
        if step % temp_control_period == 1
            rescale_temperature!(
                system(state),
                model,
                temperature
            )
        end
        state
    end
    state.stage = StageRelaxing(0, it)
    state
end
function run_stage(stage::StageRelaxing, state, callback)
    it = stage.iteration
    setup = state.setup
    relax_steps = setup.relax_steps
    relax_iterations = setup.relax_iterations
    @info "[$it/$relax_iterations] Relaxing for $relax_steps steps..."
    _run_until(state, relax_steps, stage.step) do state, step
        state.stage = StageRelaxing(step, it)
        callback(state)
    end
    if it < relax_iterations
        state.stage = StageRescalingTemperature(0, it + 1)
    else
        state.stage = StageDataCollecting(0)
    end
    state
end
function run_stage(stage::StageDataCollecting, state, callback)
    setup = state.setup
    data_steps = setup.data_steps
    taping_period = setup.taping_period
    @info "Collecting data for $data_steps steps..."
    _run_until(state, data_steps, stage.step) do state, step
        state.stage = StageDataCollecting(step)
        callback(state)
        if !isnothing(state.tape_files) && step % taping_period == 1
            update!(state.tape_files, state)
        end
    end
    state.stage = StageFinish
    state
end

function Base.run(
    setup::MDSetup;
    state::Nullable{MDState}=nothing,
    callback::Nullable{Function}=nothing,
    return_result=true
)
    if callback === nothing
        callback = default_callback(setup)
    end
    if state === nothing
        state = init_state(setup)
    end
    while state.stage ≢ StageFinish
        state = run_stage(state.stage, state, callback)
    end
    if return_result
        MDResult(
            if isnothing(state.tape_files)
                s = system(state)
                SimulationTape([state.time], [positions(s)], [velocities(s)], [periods(s)])
            else
                MultiFileMemoryMapTape(
                    setup.output_dir, setup.model,
                    has_ps=has_pbc(setup.model)
                )
            end
        )
    end
end
