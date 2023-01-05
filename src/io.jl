
function init_output(setup::MDSetup)
    datapath = setup.output_dir
    isdir(datapath) || mkpath(datapath)
    setup_file = joinpath(datapath, "setup.jld")
    jldopen(setup_file, "w") do file
        write(file, "setup", setup)
    end
end

function prepare_tape(
    output_dir::AbstractString,
    has_periods::Bool,
    taping_period::Integer;
    filename_prefix="tape",
    force=false
)
    taping_period ≤ 0 && return nothing
    files = [joinpath(output_dir, "$filename_prefix-$x.dat") for x in ("ts", "rs", "vs", "ps")]
    if any(isfile.(files))
        if force
            rm.(files, force=true)
        else
            error("Output files already exist. Use force=true to overwrite.")
        end
    end
    TapeFiles(output_dir; has_ps=has_periods, read=false, filename_prefix)
end

prepare_tape(setup::MDSetup; force=false) =
    prepare_tape(setup.output_dir, has_pbc(setup.model), setup.taping_period; force)
