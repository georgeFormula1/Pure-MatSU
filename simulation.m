% SIMULATION Top-level simulation script
% Sets up the simulation framework, instantiates objects and contains the main simulation loop.
% Do NOT edit this file, use the simulation_options function instead!
% DO Run this script to start the simulation.
%
% Inputs:
%    (none)
%
% Outputs:
%    Generates the sim_output workspace variable with members:
%    array_inputs - mxN array, where m is the size of the serialized state vector, N is the number of simulation frames
%    array_states - lxN array, where l is the number of vehicle control inputs (commonly 4) and N is the number of
%    simulation frames
%
% Other m-files required: Vehicle, Gravity, Environment, Propulsion, Aerodynamics, Kinematics, VehcileState,
% draw_aircraft, draw_forces, draw_states
% Subfunctions: none
% MAT-files required: none
%
% See also: simulation_options

% Created at 2018/02/15 by George Zogopoulos-Papaliakos

close all;
clear;
clc;

% Enable warnings
warn_state = warning('on','all');

% load_path;

%% Initialize the simulation

fprintf('Initializing simulation options...\n');

% Generate simulation options
sim_options = simulation_options();

% Initialize the simulation components, bar the controller
supervisor = Supervisor(sim_options);

% If sim_options.controller.type == 1, then the aircraft must be trimmed
if sim_options.controller.type==1
    trimmer = Trimmer(sim_options); % Instantiate the trimming object
    trimmer.calc_trim();
    trim_state = trimmer.get_trim_state(); % Get the trim state
    init_vec_euler = trim_state.get_vec_euler(); % Re-set the initialization state to the trim states
    sim_options.init.vec_euler(1:2) = init_vec_euler(1:2);
    sim_options.init.vec_vel_linear_body = trim_state.get_vec_vel_linear_body();
    sim_options.init.vec_vel_angular_body = trim_state.get_vec_vel_angular_body();
    trim_controls = trimmer.get_trim_controls(); % Get and set the trim controls
    sim_options.controller.static_output = trim_controls;
    
    % Clear internal variables
    if sim_options.delete_temp_vars
        clear trimmer trim_state trim_controls init_vec_euler
    end
    
end

% Initialize the simulation state
supervisor.initialize_sim_state(sim_options);

% Initialize the vehicle controller
supervisor.initialize_controller(sim_options);

% Setup time vector
t_0 = sim_options.solver.t_0;
t_f = sim_options.solver.t_f;
frame_skip = 100;

if sim_options.visualization.draw_forces
    plot_forces(gravity, propulsion, aerodynamics, 0, true);    
end
if sim_options.visualization.draw_states
    plot_states(vehicle, 0, true);    
end

%% Begin simulation

fprintf('Starting simulation...\n');

wb_h = waitbar(0, 'Simulation running...');

% Main loop:
tic

% Choose ODE solver
if sim_options.solver.solver_type == 0 % Forward-Euler selected

    frame_num = 1;
    t = t_0;
    dt = sim_options.solver.dt;
    num_frames = (t_f-t_0)/dt;
    
    while (t_f - t > sim_options.solver.t_eps)

        % Calculate the state derivatives
        supervisor.sim_step(t);
        
        % Integrate the internal state with the calculated derivativess
        supervisor.integrate_fe();

        % Update waitbar
        if mod(frame_num, frame_skip)==0
            waitbar(frame_num/num_frames, wb_h);
        end

        % Update visual output
        if sim_options.visualization.draw_graphics
            draw_aircraft(supervisor.vehicle, false);
        end
        if sim_options.visualization.draw_forces
            plot_forces(supervisor.gravity, supervisor.propulsion, supervisor.aerodynamics, t, false);
        end
        if sim_options.visualization.draw_states
            plot_states(supervisor.vehicle, t, false);
        end

        t = t + dt;
        frame_num = frame_num+1;

    end
    
    % Export simulation results
    if (sim_options.record_states)
        sim_output.array_time_states = supervisor.array_time_states;
        sim_output.array_states = supervisor.array_states;
    end
    if (sim_options.record_inputs)
        sim_output.array_time_inputs = supervisor.array_time_inputs;
        sim_output.array_inputs = supervisor.array_inputs;
    end
    
    % Clear internal variables
    if sim_options.delete_temp_vars
        clear array_inputs array_states vehicle_state_new temp_state ctrl_input
        clear vec_aerodynamics_force_body vec_aerodynamics_torque_body vec_force_body vec_torque_body vec_gravity_force_body vec_propulsion_force_body vec_propulsion_torque_body
        clear num_frames frame_num frame_skip
        clear t dt
    end
    

elseif ismember(sim_options.solver.solver_type, [1 2]) % Matlab ode* requested
    
    % Set initial problem state
    y0 = supervisor.vehicle.state.serialize();
    % Set system function
    odefun = @supervisor.ode_eval;
    options = odeset('outputFcn', @supervisor.ode_outputFcn);
    
    if sim_options.solver.solver_type == 1 % If ode45 requested
        
        [t, y] = ode45(odefun, [t_0 t_f], y0, options);
        
    elseif sim_options.solver.solver_type == 2 % If ode15s requested
        
        [t, y] = ode15s(odefun, [t_0 t_f], y0, options);
        
    end
    
    % Export simulation results
    if (sim_options.record_states)
        sim_output.array_time_states = t';
        sim_output.array_states = y';
    end
    if (sim_options.record_inputs)
        warning('Using Matlab''s ode solvers does not allow saving of control inputs at the returned time vector');
        sim_output.array_time_inputs = supervisor.array_time_inputs;
        sim_output.array_inputs = supervisor.array_inputs;
    end
    
    % Clear internal variables
    if sim_options.delete_temp_vars
        clear y0 y t odefun options
    end
    
else
    error('Unsupported solver_type=%d specified',sim_options.solver.solver_type);
end

wall_time = toc;
% Close waitbar
close(wb_h);

fprintf('Simulation ended\n\n');

fprintf('Simulation duration: %f\n', t_f-t_0);
fprintf('Required wall time: %f\n', wall_time);
fprintf('Achieved speedup ratio: %f\n', (t_f-t_0)/wall_time);

% Restore warnign state
warning(warn_state);

% Clear internal variables
if sim_options.delete_temp_vars
    clear supervisor temp_state
    clear wall_time t_0 t_f num_frames frame_skip wb_h
    clear warn_state
end