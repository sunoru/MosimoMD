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
    state
end

function _run_until(f, state, target, step=0)
    while step < target
        step += 1
        f(state, step)
        evolve!(state)
    end
end

run_stage(::typeof(StageBegin), state, callback) = (state.stage = StageInitial(0); state)
function run_stage(stage::StageInitial, state, callback)
    _run_until(state, state.setup.initial_steps, stage.step) do state, step
        state.stage = StageInitial(step)
        callback(state)
    end
    state.stage = StageCooling(0)
    state
end
function run_stage(stage::StageCooling, state, callback)
    _run_until(state, state.setup.cooling_steps, stage.step) do state, step
        state.stage = StageCooling(step)
        callback(state)
    end
    state.stage = StageRescalingTemperature(0, 1)
    state
end
function run_stage(stage::StageRescalingTemperature, state, callback)
    it = stage.iteration
    _run_until(state, state.setup.temp_control_steps, stage.step) do state, step
        state.stage = StageRescalingTemperature(step, it)
        callback(state)
    end
    state.stage = StageRelaxing(0, it)
    state
end
function run_stage(stage::StageRelaxing, state, callback)
    it = stage.iteration
    _run_until(state, state.setup.relax_steps, stage.step) do state, step
        state.stage = StageRelaxing(step, it)
        callback(state)
    end
    if it < state.setup.relax_iterations
        state.stage = StageRescalingTemperature(0, it + 1)
    else
        state.stage = StageDataCollecting(0)
    end
    state
end
function run_stage(stage::StageDataCollecting, state, callback)
    _run_until(state, state.setup.data_steps, stage.step) do state, step
        state.stage = StageDataCollecting(step)
        callback(state)
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
        # TODO: tape
        # return MDResult(state)
    end
end

# function evolve!(state::MDState; callback::Nullable{Function} = nothing)
#     _, δt = move!(state.integrator)
#     s = system(state)
#     if has_pbc(s)
#         update_periods!(s)
#     end
#     state.step += 1
#     state.time += δt
#     if callback !== nothing
#         callback(state)
#     end
#     state
# end

# function prepare_sampling(setup_state::MDState, setup::MDSetup, state_files::MDStateFiles)
#     observables = setup.observables
#     block_size = setup.block_size
#     sampling_period::Int = setup.sampling_period
#     block_buffer_size::Int = block_size ÷ sampling_period
#     blocks::Vector{ObservableBlock} = ObservableBlock[ObservableBlock(o, block_buffer_size) for o in observables]
#     predata = predata_steps(setup)
#     t = (setup_state.step - predata) ÷ sampling_period
#     @assert t % block_buffer_size === 0
#     sample_i = Ref(0)
#     sampling_step = Ref( (t + 1) * sampling_period + predata)
#     model = setup.model
#     function do_sample(state::MDState)
#         if state.step === sampling_step[]
#             sample_i[] += 1
#             sample!(blocks, system(state), model, sample_i[])
#             if sample_i[] === block_buffer_size
#                 save_observables(state_files, state.time, (mean(block) for block in blocks)...)
#                 sample_i[] = 0
#             end
#             sampling_step[] += sampling_period
#         end
#         state
#     end
#     do_sample
# end

# function predata_run(setup, logging, callback)
#     sampling_period = setup.sampling_period
#     block_size = setup.block_size
#     logging_period = setup.logging_period
#     taping_period = setup.taping_period

#     model = setup.model
#     _, state_files = load_state(setup, 0)
#     state = init_state(model, setup)
#     save_state(state_files, state)
#     @info "MD started."
#     if callback !== nothing
#         callback(state)
#     end

#     logging(state)
#     initial_steps = setup.initial_steps
#     initialize_step = initialize_procedure(setup, model)
#     @info "Initializing..."
#     while state.step < initial_steps
#         evolve!(state)
#         initialize_step(state)
#         if callback !== nothing
#             callback(state)
#         end
#     end
#     @info "Initialized for $(initial_steps) steps."

#     logging(state)
#     cooling_steps = state.step + setup.cooling_steps
#     cooling_step = state.step
#     target_temperature = setup.compressed_temperature
#     temperature_step_size = (target_temperature - setup.temperature) / (cooling_steps ÷ block_size)
#     @info "Cooling down..."
#     while true
#         if state.step === cooling_step
#             rescale_temperature!(system(state), model, target_temperature)
#             cooling_step += block_size
#             target_temperature -= temperature_step_size
#         end
#         if state.step >= cooling_steps
#             break
#         end
#         evolve!(state; callback = callback)
#     end
#     @info "Cooled for $(cooling_steps) steps."

#     target_temperature = setup.temperature
#     block_buffer_size = block_size ÷ sampling_period
#     relax_iterations = setup.relax_iterations
#     relax_i = 0
#     while relax_i < relax_iterations
#         relax_i += 1
#         logging(state)
#         temp_control_step = state.step
#         temp_control_steps = temp_control_step + setup.temp_control_steps
#         @info "($(relax_i)) Rescaling temperature for $(setup.temp_control_steps) steps..."
#         while state.step < temp_control_steps
#             if state.step === temp_control_step
#                 rescale_temperature!(system(state), model, target_temperature)
#                 temp_control_step += block_size
#             end
#             evolve!(state; callback = callback)
#         end
#         relax_steps = state.step + setup.relax_steps
#         @info "($(relax_i)) Relaxing for equlibrium for $(setup.relax_steps) steps..."
#         while state.step < relax_steps
#             evolve!(state; callback = callback)
#         end
#     end
#     state, state_files
# end

# function run(
#     setup::MDSetup;
#     state::Nullable{MDState} = nothing,
#     callback::Nullable{Function} = nothing,
# )
#     sampling_period = setup.sampling_period
#     block_size = setup.block_size
#     logging_period = setup.logging_period
#     checkpoint_period = setup.checkpoint_period
#     taping_period = setup.taping_period

#     if !no_logging && logging === nothing
#         logging = default_logging(setup)
#     end

#     loaded = state !== nothing
#     predata = predata_steps(setup)
#     if state === nothing
#         state, state_files = predata_run(setup, logging, callback)
#         @assert state.step === predata
#     end

#     run_steps = predata + setup.run_steps
#     logging_step = loaded ?
#         ((state.step - predata) ÷ logging_period + 1) * logging_period + predata :
#         state.step
#     checkpoint_step = loaded ?
#         ((state.step - predata) ÷ checkpoint_period + 1) * checkpoint_period + predata :
#         state.step
#     taping_step = loaded ?
#         ((state.step - predata) ÷ taping_period  + 1) * taping_period + predata :
#         state.step
#     do_sample = prepare_sampling(state, setup, state_files)

#     no_logging || @info "Start collecting data..."
#     while true
#         if !no_logging && state.step === logging_step
#             logging(state)
#             logging_step += logging_period
#         end
#         if state.step === taping_step
#             update_tape(state_files, state)
#             taping_step += taping_period
#         end
#         if state.step === checkpoint_step
#             save_state(state_files, state)
#             checkpoint_step += checkpoint_period
#         end
#         do_sample(state)
#         if state.step >= run_steps
#             break
#         end
#         evolve!(state; callback = callback)
#     end
#     if !no_logging && state.step !== logging_step - logging_period
#         logging(state)
#     end
#     close(state_files)

#     no_logging || @info "MD finished."

#     result = return_result ? load_result(setup; mmap = mmap) : nothing
# end