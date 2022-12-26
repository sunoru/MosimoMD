using Test

using Pkg
Pkg.develop(url="https://github.com/sunoru/mosimo-examples.git", subdir="LJClusters")

using MosimoBase
using LJClusters

using MosimoMD

@testset "Simple MD (LJ Cluster)" begin

N = 8
ρ = 0.8
L = (N / ρ)^(1/3)
model = LJCluster3D(N, box=Vector3(L, L, L))

setup = md_init(;
    timestep = 0.01,
    temperature = 1.0,
    compressed_temperature = 3.0,
    temp_control_period = 25,
    initial_steps = 200,
    cooling_steps = 200,
    temp_control_steps = 200,
    relax_steps = 200,
    relax_iterations = 3,
    data_steps = 1000,
    taping_period = 10,
    output_dir = joinpath(@__DIR__, "out/simple"),
    seed = 95813,
    model
)

function make_callback(setup)
    cb = MosimoMD.default_callback(setup, 100)
    function callback(state::MDState)
        if step(state) % 100 == 1
            @show state.stage
        end
        cb(state)
    end
end

callback = make_callback(setup)

result = run(setup; callback, force=true)

KEs = Float64[]
PEs = Float64[]

for i in 1:length(result.tape)
    s = system(result, i)
    push!(KEs, kinetic_energy(s, model))
    push!(PEs, potential_energy(s, model))
end

@test length(result.tape) == 100
@test mean(KEs) ≈ 13.07641033325682
@test mean(PEs) ≈ -18.821001206035277
@test std(KEs + PEs) ≤ 0.2

end
