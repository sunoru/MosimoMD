# overridable for different models
function rescale_temperature!(system::MosiSystem, model::MosiModel, T::Real)
    current_temperature = temperature(system, model)
    scale = √(T / current_temperature)
    velocities(system) .*= scale
    system
end
