Base.@kwdef struct MDSetup{M<:MosiModel,I<:IntegratorParameters} <: SimulationSetup
    timestep::Float64
    temperature::Float64

    compressed_temperature::Float64
    temp_control_period::Int

    initial_steps::Int
    cooling_steps::Int
    temp_control_steps::Int
    relax_steps::Int
    relax_iterations::Int
    data_steps::Int

    taping_period::Int
    output_dir::String

    seed::UInt64

    model::M
    integrator_params::I
end

# not used
predata_steps(setup::MDSetup) = step(StageDataCollecting(0), setup)

@data MDStage begin
    StageBegin
    StageInitial(step::Int)
    StageCooling(step::Int)
    StageRescalingTemperature(step::Int, iteration::Int)
    StageRelaxing(step::Int, iteration::Int)
    StageDataCollecting(step::Int)
    StageFinish
end

Base.@kwdef mutable struct MDState{
    TRNG<:AbstractRNG,
    TIntegrator<:AbstractIntegrator,
    TSystem<:MolecularSystem,
    TSetup<:MDSetup,
    TTapeFiles<:Nullable{TapeFiles}
} <: SimulationState
    const rng::TRNG
    const integrator::TIntegrator
    const system::TSystem
    const setup::TSetup
    const tape_files::TTapeFiles
    stage::MDStage = StageBegin
    time::Float64 = 0.0
end

MosimoBase.system(state::MDState) = state.system
Base.time(state::MDState) = state.time
function Base.step(stage::MDStage, setup::MDSetup)
    stage ≡ StageBegin && return 0
    stage isa StageInitial && return stage.step
    ss = setup.initial_steps
    stage isa StageCooling && return ss + stage.step
    ss += setup.cooling_steps
    rs = setup.temp_control_steps + setup.relax_steps
    stage isa StageRescalingTemperature && return ss + rs * (stage.iteration - 1) + stage.step
    stage isa StageRelaxing && return ss + rs * (stage.iteration - 1) + setup.temp_control_steps + stage.step
    ss += rs * setup.relax_iterations
    stage isa StageDataCollecting && return ss + stage.step
    # StageFinish
    ss + setup.data_steps
end
Base.step(state::MDState) = step(state.stage, state.setup)

struct MDResult <: SimulationResult
    tape::SimulationTape
end

MosimoBase.system(result::MDResult, i::Integer=length(result.tape)) =
    system(result.tape, i)