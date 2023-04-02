function default_callback(setup::MDSetup, logging_period=min(5000, setup.data_steps / 10))
    @assert logging_period > 0
    model = setup.model
    (state::MDState) -> begin
        @match state.stage begin
            StageBegin => println(" Step |   Time   |  Potential  |   Kinetic   |    Total")
            StageFinish => return
            stage => if stage.step != 1 && step(state) % logging_period ≠ 0
                return
            end
        end
        s = system(state)
        kinetic = kinetic_energy(s, model)
        potential = potential_energy(s, model)
        total = potential + kinetic
        @printf "%5d |%9.5f |%12.4e |%12.4e |%12.4e\n" step(state) state.time potential kinetic total
        flush(stdout)
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

# default to no-op
stage_callback(::MDSetup, stage::Type{<:MDStage}) = (state::MDState, step::Int) -> state

function _run_until(f::F, state, target, step=0) where F
    while step < target
        step += 1
        f(state, step)
        evolve!(state)
    end
end

function run_stage(::typeof(StageBegin), state, callback::F) where F
    callback(state)
    stage_callback(state.setup, typeof(StageBegin))(state, 0)
    state.stage = StageInitial(0)
    state
end
function run_stage(stage::StageInitial, state, callback::F) where F
    initial_steps = state.setup.initial_steps
    @info "Initial $initial_steps steps..."
    scb = stage_callback(state.setup, StageInitial)
    _run_until(state, initial_steps, stage.step) do state, step
        state.stage = StageInitial(step)
        callback(state)
        scb(state, step)
    end
    state.stage = StageCooling(0)
    state
end
function run_stage(stage::StageCooling, state, callback::F) where F
    setup = state.setup
    cooling_steps = setup.cooling_steps
    temp_control_period = setup.temp_control_period
    model = setup.model
    compressed_temperature = setup.compressed_temperature
    @info "Cooling for $cooling_steps steps..."
    scb = stage_callback(setup, StageCooling)
    _run_until(state, cooling_steps, stage.step) do state, step
        state.stage = StageCooling(step)
        callback(state)
        scb(state, step)
        if step % temp_control_period == 0
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
function run_stage(stage::StageRescalingTemperature, state, callback::F) where F
    it = stage.iteration
    setup = state.setup
    temp_control_steps = setup.temp_control_steps
    temp_control_period = setup.temp_control_period
    temperature = setup.temperature
    model = setup.model
    @info "[$it/$(state.setup.relax_iterations)] Rescaling temperature for $temp_control_steps steps..."
    scb = stage_callback(setup, StageRescalingTemperature)
    _run_until(state, temp_control_steps, stage.step) do state, step
        state.stage = StageRescalingTemperature(step, it)
        callback(state)
        scb(state, step)
        if step % temp_control_period == 0
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
function run_stage(stage::StageRelaxing, state, callback::F) where F
    it = stage.iteration
    setup = state.setup
    relax_steps = setup.relax_steps
    relax_iterations = setup.relax_iterations
    @info "[$it/$relax_iterations] Relaxing for $relax_steps steps..."
    scb = stage_callback(setup, StageRelaxing)
    _run_until(state, relax_steps, stage.step) do state, step
        state.stage = StageRelaxing(step, it)
        callback(state)
        scb(state, step)
    end
    if it < relax_iterations
        state.stage = StageRescalingTemperature(0, it + 1)
    else
        state.stage = StageDataCollecting(0)
    end
    state
end
function run_stage(stage::StageDataCollecting, state, callback::F) where F
    setup = state.setup
    data_steps = setup.data_steps
    taping_period = setup.taping_period
    @info "Collecting data for $data_steps steps..."
    scb = stage_callback(setup, StageDataCollecting)
    _run_until(state, data_steps, stage.step) do state, step
        state.stage = StageDataCollecting(step)
        callback(state)
        scb(state, step)
        if !isnothing(state.tape_files) && step % taping_period == 0
            update!(state.tape_files, state)
        end
    end
    state.stage = StageFinish
    state
end

function md_run(
    setup::MDSetup;
    state::Nullable{MDState}=nothing,
    callback::Nullable{F}=nothing,
    return_result=true,
    force=false
) where {F <: Function}
    if callback === nothing
        callback = default_callback(setup)
    end
    if state === nothing
        state = init_state(setup; force)
    end
    @info "MD started from $(state.stage)."
    while state.stage ≢ StageFinish
        state = run_stage(state.stage, state, callback)
    end
    close(state.tape_files)
    @info "MD finished."
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
