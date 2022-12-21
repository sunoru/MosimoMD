function md_init(;
    timestep::Real,
    temperature::Real,
    compressed_temperature::Real,
    temp_control_period::Integer,
    initial_steps::Integer,
    cooling_steps::Integer,
    temp_control_steps::Integer,
    relax_steps::Integer,
    relax_iterations::Integer,
    data_steps::Integer,
    taping_period::Integer=0,
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
        compressed_temperature, temp_control_period,
        initial_steps, cooling_steps,
        temp_control_steps, relax_steps, relax_iterations,
        data_steps,
        taping_period,
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
    tape_files = prepare_tape(setup)
    state = MDState(;
        rng,
        integrator,
        system,
        setup,
        tape_files
    )
end
