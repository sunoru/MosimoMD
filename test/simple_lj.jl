using Test

using Pkg
Pkg.add(url="https://github.com/sunoru/mosimo-examples.git", subdir="LJClusters")

using MosimoBase
using LJClusters

using MosimoMD

@testset "Simple MD (LJ Cluster)" begin

N = 8
model = LJCluster3D(N)

setup = md_init(;
    timestep = 0.01,
    temperature = 1.0,
    initial_steps = 200,
    compressed_temperature = 3.0,
    cooling_steps = 200,
    temp_control_steps = 200,
    relax_steps = 200,
    relax_iterations = 3,
    data_steps = 1000,
    checkpoint_period = 200,
    output_dir = joinpath(@__DIR__, "out/simple"),
    seed = 95813,
    model
)

function make_callback(model)
    Ks = Float64[]
    Us = Float64[]

    function callback(state::MDState; force_logging = false)
        s = step(state)
        if s % 50 == 0
            @show s state.stage
        end
        # @match state.stage begin
        #     StageBegin => begin
        #         @info "MD started."
        #     end
        # end
    end
end

callback = make_callback(model)

result = run(setup; callback)

end
