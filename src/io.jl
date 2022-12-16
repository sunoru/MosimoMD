
function init_output(setup::MDSetup)
    datapath = setup.output_dir
    isdir(datapath) || mkpath(datapath)
    setup_file = joinpath(datapath, "setup.yaml")
    open(setup_file, "w") do io
        YAML.print(io, setup)
    end
end

function prepare_tape(
    output_dir::AbstractString, taping_period::Integer,
    has_periods::Bool;
    filename_prefix="tape"
)
    tf = TapeFiles(output_dir; has_ps=has_periods, read=false, filename_prefix)
    function update!(state::MDState)
        @match state.stage begin
            StageDataCollecting(step) && if step % taping_period == 0
            end =>
                update_tape!(tf, state)
        end
        tf
    end
    update!
end

prepare_tape(setup::MDSetup, taping_period::Integer) =
    prepare_tape(setup.output_dir, taping_period, has_pbc(setup.model))
