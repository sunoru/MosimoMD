function md_init(;
    timestep::Real,
    temperature::Real,
    initial_steps::Integer,
    compressed_temperature::Real,
    cooling_steps::Integer,
    temp_control_steps::Integer,
    relax_steps::Integer,
    relax_iterations::Integer,
    data_steps::Integer,
    checkpoint_period::Integer=data_steps / 10,
    output_dir::AbstractString,
    seed::Nullable{Integer}=nothing,
    model::MosiModel=UnknownModel(),
    integrator_params::IntegratorParameters=VerletParameters()
)
    if model isa UnknownModel
        throw(SimulationError("model not defined"))
    end

    seed = make_seed(seed)

    setup = MDSetup(;
        timestep,
        temperature,
        initial_steps, compressed_temperature, cooling_steps,
        temp_control_steps, relax_steps, relax_iterations,
        data_steps,
        checkpoint_period,
        output_dir,
        seed,
        model,
        integrator_params
    )

    init_output(setup)

    setup
end

function init_output(setup::MDSetup)
    datapath = setup.output_dir
    isdir(datapath) || mkpath(datapath)
    setup_file = joinpath(datapath, "setup.yaml")
    open(setup_file, "w") do io
        YAML.print(io, setup)
    end
end

# Use verlet as default integrator.
get_integrator(setup::MDSetup, system::MosiSystem) = VerletIntegrator(
    positions(system), velocities(system),
    setup.timestep,
    i -> mass(setup.model, i),
    rs -> force_function(setup.model, rs)
)

function init_state(setup::MDSetup)
    rng = new_rng(setup.seed)
    system = MosimoBase.generate_initial(setup.model, MolecularSystem; rng)
    integrator = get_integrator(setup, system)
    state = MDState(;
        rng,
        integrator,
        system,
        setup
    )
end
