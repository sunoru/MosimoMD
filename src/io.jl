
function init_output(setup::MDSetup)
    datapath = setup.output_dir
    isdir(datapath) || mkpath(datapath)
    setup_file = joinpath(datapath, "setup.yaml")
    open(setup_file, "w") do io
        YAML.print(io, setup)
    end
end

function prepare_tape(
    output_dir::AbstractString,
    has_periods::Bool,
    taping_period::Integer;
    filename_prefix="tape"
)
    taping_period ≤ 0 && return nothing
    TapeFiles(output_dir; has_ps=has_periods, read=false, filename_prefix)
end

prepare_tape(setup::MDSetup) =
    prepare_tape(setup.output_dir, has_pbc(setup.model), setup.taping_period)
