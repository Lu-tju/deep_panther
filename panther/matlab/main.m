% /* ----------------------------------------------------------------------------
%  * Copyright 2021, Jesus Tordesillas Torres, Aerospace Controls Laboratory
%  * Massachusetts Institute of Technology
%  * All Rights Reserved
%  * Authors: Jesus Tordesillas, et al.
%  * See LICENSE file for the license information
%  * -------------------------------------------------------------------------- */

close all; clc;clear;
doSetup();
import casadi.*

const_p={};    const_y={};
opti = casadi.Opti();

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% CONSTANTS! %%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

pos_is_fixed=false; %you need to run this file twice to produce the necessary casadi files: both with pos_is_fixed=false and pos_is_fixed=true. 

optimize_n_planes=true;     %Optimize the normal vector "n" of the planes
optimize_d_planes=true;     %Optimize the scalar "d" of the planes
optimize_time_alloc=true;

soft_dynamic_limits_constraints=false;
soft_obstacle_avoid_constraint=false;

make_plots=false;


deg_pos=3;
deg_yaw=2;
num_seg =6; %number of segments
num_max_of_obst=1; %This is the maximum num of the obstacles 

%Constants for spline fitted to the obstacle trajectory
fitter.deg_pos=3;
fitter.num_seg=7;
fitter.dim_pos=3;
fitter.num_samples=20;
fitter_num_of_cps= fitter.num_seg + fitter.deg_pos;
for i=1:num_max_of_obst
    fitter.ctrl_pts{i}=opti.parameter(fitter.dim_pos,fitter_num_of_cps); %This comes from C++
    fitter.bbox_inflated{i}=opti.parameter(fitter.dim_pos,1); %This comes from C++
    fitter.bs_casadi{i}=MyCasadiClampedUniformSpline(0,1,fitter.deg_pos,fitter.dim_pos,fitter.num_seg,fitter.ctrl_pts{i}, false);
end
fitter.bs=       MyClampedUniformSpline(0,1, fitter.deg_pos, fitter.dim_pos, fitter.num_seg, opti);
fitter.total_time=6.0; %Time from (time at point d) to end of the fitted spline
%%%%%%%%%%%%%%%%%%%%%%%%%%%



sampler.num_samples_obstacle_per_segment = 4;                    %This is used for both the feature sampling (simpson), and the obstacle avoidance sampling
sampler.num_samples=sampler.num_samples_obstacle_per_segment*num_seg;    %This will also be the num_of_layers in the graph yaw search of C++
                                                             

num_of_yaw_per_layer=40; %This will be used in the graph yaw search of C++
                         %Note that the initial layer will have only one yaw (which is given) 
basis="MINVO"; %MINVO OR B_SPLINE or BEZIER. This is the basis used for collision checking (in position, velocity, accel and jerk space), both in Matlab and in C++
linear_solver_name='ma27'; %mumps [default, comes when installing casadi], ma27, ma57, ma77, ma86, ma97 
print_level=0; %From 0 (no verbose) to 12 (very verbose), default is 5
jit=false;

t0_n=0.0; 
tf_n=1.0;

dim_pos=3;
dim_yaw=1;

offset_vel=0.1;

assert(tf_n>t0_n);

assert(t0_n==0.0); %This must be 0 (assummed in the C++ and MATLAB code)
assert(tf_n==1.0); %This must be 1 (assummed in the C++ and MATLAB code)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% PARAMETERS! %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%% DEFINITION
%%%%% factors for the cost
c_pos_smooth= opti.parameter(1,1);
c_yaw_smooth= opti.parameter(1,1);
c_fov=        opti.parameter(1,1);
c_final_pos = opti.parameter(1,1);
c_final_yaw = opti.parameter(1,1);
c_total_time = opti.parameter(1,1);
% c_dyn_lim= opti.parameter(1,1);
% c_costs.dist_im_cost=         opti.parameter(1,1);

Ra=opti.parameter(1,1);

thetax_FOV_deg=opti.parameter(1,1);    %total angle of the FOV in the x direction
thetay_FOV_deg=opti.parameter(1,1);    %total angle of the FOV in the y direction

thetax_half_FOV_deg=thetax_FOV_deg/2.0; %half of the angle of the cone
thetax_half_FOV_rad=thetax_half_FOV_deg*pi/180.0;

thetay_half_FOV_deg=thetay_FOV_deg/2.0; %half of the angle of the cone
thetay_half_FOV_rad=thetay_half_FOV_deg*pi/180.0;

%%%%% Transformation matrix camera/body b_T_c
b_T_c=opti.parameter(4,4);

if(optimize_time_alloc)
    alpha=opti.variable(1,1); 
else
    alpha=opti.parameter(1,1); 
end
total_time=alpha*(tf_n-t0_n); %Total time is (tf_n-t0_n)*alpha. 


%%%%% Initial and final conditions, and max values
%FOR POSITION
p0=opti.parameter(3,1); v0=opti.parameter(3,1); a0=opti.parameter(3,1);
pf=opti.parameter(3,1); vf=opti.parameter(3,1); af=opti.parameter(3,1);

v_max=opti.parameter(3,1);
a_max=opti.parameter(3,1);
j_max=opti.parameter(3,1);

%Normalized v0, a0, v_max,...
v0_n=v0*alpha;
a0_n=a0*(alpha^2);
vf_n=vf*alpha;
af_n=af*(alpha^2);
v_max_n=v_max*alpha;
a_max_n=a_max*(alpha^2); 
j_max_n=j_max*(alpha^3);

%FOR YAW
y0=opti.parameter(1,1); ydot0=opti.parameter(1,1); 
yf=opti.parameter(1,1); ydotf=opti.parameter(1,1);
ydot_max=opti.parameter(1,1);

ydot0_n=ydot0*alpha;
ydotf_n=ydotf*alpha;
ydot_max_n=ydot_max*alpha; %v_max for yaw


%%%%% Planes
n={}; d={};
for i=1:(num_max_of_obst*num_seg)
    if(optimize_n_planes)
        n{i}=opti.variable(3,1); 
    else
        n{i}=opti.parameter(3,1); 
    end
  
    if(optimize_d_planes)
        d{i}=opti.variable(1,1);
    else
        d{i}=opti.parameter(1,1); 
    end    
end



% obstacle_bbox_inflated={};
% for i=1:num_max_of_obst
%     obstacle_bbox_inflated{i}=opti.parameter(3,1); %It has three elements: hx, hy, hz (bbox_inflated of size hx x hy x hz)
% end



%%% Min/max x, y ,z
x_lim=opti.parameter(2,1); %[min max]
y_lim=opti.parameter(2,1); %[min max]
z_lim=opti.parameter(2,1); %[min max]

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% CREATION OF THE SPLINES! %%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sy=MyClampedUniformSpline(t0_n,tf_n,deg_yaw, dim_yaw, num_seg, opti); %spline yaw.

if(pos_is_fixed==true)
    sp=MyClampedUniformSpline(t0_n,tf_n,deg_pos, dim_pos, num_seg, opti, false); %spline position, cPoints are fixed
else
    sp=MyClampedUniformSpline(t0_n,tf_n,deg_pos, dim_pos, num_seg, opti); %spline position.
end



%%%%%%%% Trajectory of the obstacle
% N=num_seg+deg_pos+1;
% deg_obstacle=deg_pos;
% dim_obstacle=dim_pos;

% p=deg_obstacle;
% t_obs=linspace(0,1,num_seg+1);
% knots_obstacle=[zeros(1,p+1)      t_obs(2:end-1)          ones(1,p+1)];





%This part below uses the Casadi implementation of a BSpline. However, that
%implementation does not allow SX variables (which means that it cannot be
%expanded). See more at https://github.com/jtorde/useful_things/blob/master/casadi/bspline_example/bspline_example.m
% t_eval_sym=MX.sym('t_eval_sym',1,1); 
% %See https://github.com/jtorde/useful_things/blob/master/casadi/bspline_example/bspline_example.m
% my_bs_parametric_tmp=casadi.bspline(t_eval_sym, fitter.ctrl_pts(:), {knots_obstacle}, {[deg_obstacle]}, dim_obstacle); %Note that here we use casadi.bspline, NOT casadi.Function.bspline
% my_bs_parametric = Function('my_bs_parametric',{t_eval_sym,fitter.ctrl_pts},{my_bs_parametric_tmp});

% beta1 =opti.parameter(1,1); %deltat_fromInitTrajObs_toPointD

deltaT=total_time/num_seg; %Time allocated for each segment

obst={}; %Obs{i}{j} Contains the vertexes (as columns) of the obstacle i in the interval j

for i=1:num_max_of_obst

    all_centers=[];
    for j=1:num_seg

        all_vertexes_segment_j=[];
        
        for k=1:sampler.num_samples_obstacle_per_segment
            %This takes a sample at the end, but not at the beginning
%             t_obs = beta1 + deltaT*(j-1) + (k/sampler.num_samples_obstacle_per_segment)*deltaT;
            t_obs = deltaT*(j-1) + (k/sampler.num_samples_obstacle_per_segment)*deltaT;
            
            t_nobs= max( t_obs/fitter.total_time,  1.0 );  %Note that fitter.bs_casadi{i}.knots=[0...1]
            
            pos_center_obs=fitter.bs_casadi{i}.getPosT(t_nobs);
            
            all_centers=[all_centers pos_center_obs];

            all_vertexes_segment_j=[all_vertexes_segment_j vertexesOfBox(pos_center_obs, fitter.bbox_inflated{i}) ];

        end

        obst{i}.vertexes{j}=all_vertexes_segment_j;
        
    end  
    
    obst{i}.centers=all_centers;
    
end

t_opt_n_samples=linspace(0,1,sampler.num_samples);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% CONSTRAINTS! %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

total_time_n=(tf_n-t0_n);

alpha=total_time/total_time_n;  %Please read explanation_normalization.svg

v0_n=v0*alpha;
a0_n=a0*(alpha^2);
ydot0_n=ydot0*alpha;


vf_n=vf*alpha;
af_n=af*(alpha^2);
ydotf_n=ydotf*alpha;

v_max_n=v_max*alpha;
a_max_n=a_max*(alpha^2);
j_max_n=j_max*(alpha^3);

ydot_max_n=ydot_max*alpha;

%Initial conditions
const_p{end+1}= sp.getPosT(t0_n)== p0 ;
const_p{end+1}= sp.getVelT(t0_n)== v0_n ;
const_p{end+1}= sp.getAccelT(t0_n)== a0_n ;
const_y{end+1}= sy.getPosT(t0_n)== y0 ;
const_y{end+1}= sy.getVelT(t0_n)== ydot0_n ;

%Final conditions
% opti.subject_to( sp.getPosT(tf)== pf );
const_p{end+1}= sp.getVelT(tf_n)== vf_n ;
const_p{end+1}= sp.getAccelT(tf_n)== af_n ;
const_y{end+1}= sy.getVelT(tf_n)==ydotf_n ; % Needed: if not (and if you are minimizing ddyaw), dyaw=cte --> yaw will explode



%
if(optimize_time_alloc)
    const_p{end+1}= total_time<=fitter.total_time; %Samples for visibility/obs_avoidance are only taken for t<fitter.total_time
end

const_p_obs_avoid={}

% epsilon=1;
for j=1:(sp.num_seg)

    %Get the control points of the interval
    Q=sp.getCPs_XX_Pos_ofInterval(basis, j);

    %Plane constraints
    for obst_index=1:num_max_of_obst
      ip = (obst_index-1) * sp.num_seg + j;  % index plane
       
      %The obstacle should be on one side
      %I need this constraint if alpha is a dec. variable OR if n is a dec
      %variable OR if d is a dec variable
      
      if(optimize_n_planes || optimize_d_planes || optimize_time_alloc)
      
          for i=1:num_max_of_obst
            vertexes_ij=obst{i}.vertexes{j};
            for kk=1:size(vertexes_ij,2)
                const_p_obs_avoid{end+1}= n{ip}'*vertexes_ij(:,kk) + d{ip} >= 1; 
            end
          end
      
      end
      
      
      %and the control points on the other side
      for kk=1:size(Q,2)
        const_p_obs_avoid{end+1}= n{ip}'*Q{kk} + d{ip} <= -1;
      end
    end  
 
%     %Sphere constraints
%     for kk=1:size(Q,2) 
%         tmp=(Q{kk}-p0);
%         const_p{end+1}= (tmp'*tmp)<=(Ra*Ra) ;
%     end
    
    %Min max xyz constraints
    for kk=1:size(Q,2) 
        t_obs=Q{kk};
%         const_p{end+1}= x_lim(1)<=tmp(1) ;
%         const_p{end+1}= x_lim(2)>=tmp(1) ;
%         
%         const_p{end+1}= y_lim(1)<=t_obs(2) ;
%         const_p{end+1}= y_lim(2)>=t_obs(2) ;
% 
%         const_p{end+1}= z_lim(1)<=t_obs(3) ; 
%         const_p{end+1}= z_lim(2)>=t_obs(3) ;
    end
end




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% OBJECTIVE! %%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clear i

% u=MX.sym('u',1,1); %it must be defined outside the loop (so that then I can use substitute it regardless of the interval
% w_fevar=MX.sym('w_fevar',3,1); %it must be defined outside the loop (so that then I can use substitute it regardless of the interval
% w_velfewrtworldvar=MX.sym('w_velfewrtworld',3,1);
yaw= MX.sym('yaw',1,1);  
simpson_index=1;
simpson_coeffs=[];

% all_target_isInFOV=[];
all_fov_costs=[];

% s_logged={};

all_simpson_constants=[];
all_is_in_FOV_smooth=[];
fov_cost=0;
%%%%%%%%%%%%%%%%%%%%%%%%%%%

h=alpha*(t_opt_n_samples(2)-t_opt_n_samples(1));

for t_opt_n=t_opt_n_samples %TODO: Use a casadi map for this sum
    
    w_t_b = sp.getPosT(t_opt_n);
    a=sp.getAccelT(t_opt_n)/(alpha^(2));
    
    qpsi=[cos(yaw/2), 0, 0, sin(yaw/2)]; %Note that qpsi has norm=1
    qabc=qabcFromAccel(a,9.81);
    q=multquat(qabc,qpsi); %Note that q is guaranteed to have norm=1
    w_R_b=toRotMat(q);
  
    w_T_b=[w_R_b w_t_b; zeros(1,3) 1];     w_T_c=w_T_b*b_T_c;     c_T_b=invPose(b_T_c);     b_T_w=invPose(w_T_b);
    
    w_fevar=obst{1}.centers(:,simpson_index); %TODO: For now, only choosing one obstacle
    
    c_P=c_T_b*b_T_w*[w_fevar;1]; %Position of the feature in the camera frame
    s=c_P(1:2)/(c_P(3));  %Note that here we are not using f (the focal length in meters) because it will simply add a constant factor in ||s|| and in ||s_dot||
    
    %FOV is a cone:  (See more possible versions of this constraint at the end of this file)
    is_in_FOV_tmp=-cos(thetax_half_FOV_deg*pi/180.0) + (c_P(1:3)'/norm(c_P((1:3))))*[0;0;1]; % Constraint is is_in_FOV1>=0
    
    
    
    gamma=100;
    all_is_in_FOV_smooth=[all_is_in_FOV_smooth  (   1/(1+exp(-gamma*is_in_FOV_tmp))  ) ];
    
    is_in_FOV=substitute(is_in_FOV_tmp,yaw,sy.getPosT(t_opt_n));
    
    f=-is_in_FOV; % Constraint is f<=0
    
    %Penalty associated with the constraint
    %Note that that is_in_FOV_tmp \in [-2,2]
%     fov_cost_j=max(0,f)^3;  %This will try to put the obstacle in the FOV 
    %N=30;
    %fov_cost_j=log(1+exp(f*N))/N; %This is a smooth approximation of max(0,f), see https://math.stackexchange.com/a/517741/564801
    fov_cost_j=f^3;           %This will try to put the obstacle in the center of the FOV
    
    simpson_constant=(h/3.0)*getSimpsonCoeff(simpson_index,sampler.num_samples);
    
    fov_cost=fov_cost + simpson_constant*fov_cost_j; %See https://en.wikipedia.org/wiki/Simpson%27s_rule#Composite_Simpson's_rule
    
    all_fov_costs=[all_fov_costs fov_cost_j];
    
    
    
    simpson_index=simpson_index+1;
    all_simpson_constants=[all_simpson_constants simpson_constant];
    
end


%Cost
pos_smooth_cost=sp.getControlCost()/(alpha^(sp.p-1));
final_pos_cost=(sp.getPosT(tf_n)- pf)'*(sp.getPosT(tf_n)- pf);
total_time_cost=alpha*(tf_n-t0_n);
yaw_smooth_cost=sy.getControlCost()/(alpha^(sy.p-1));
final_yaw_cost=(sy.getPosT(tf_n)- yf)^2;

total_cost=c_pos_smooth*pos_smooth_cost+...
           c_fov*fov_cost+...
           c_final_pos*final_pos_cost+...
           c_yaw_smooth*yaw_smooth_cost+...
           c_final_yaw*final_yaw_cost+...
           c_total_time*total_time_cost;


%First option: Hard constraints
const_p_dyn_limits={};
const_y_dyn_limits={};
[const_p_dyn_limits,const_y_dyn_limits]=addDynLimConstraints(const_p_dyn_limits, const_y_dyn_limits, sp, sy, basis, v_max_n, a_max_n, j_max_n, ydot_max_n);


%%
opti_tmp=opti.copy;
opti_tmp.subject_to(); %Clear constraints
opti_tmp.subject_to([const_p_dyn_limits, const_y_dyn_limits]);

violation_dyn_limits=getViolationConstraints(opti_tmp);

opti_tmp=opti.copy;
opti_tmp.subject_to(); %Clear constraints
opti_tmp.subject_to([const_p_obs_avoid]);
violation_obs_avoid=getViolationConstraints(opti_tmp);

if(soft_dynamic_limits_constraints==true)
    total_cost = total_cost + (1/numel(violation_dyn_limits))*sum(violation_dyn_limits.^2);
else
    const_p=[const_p, const_p_dyn_limits];
    const_y=[const_y, const_y_dyn_limits];
end


if(soft_obstacle_avoid_constraint==true)
    total_cost = total_cost + 100*(1/numel(violation_obs_avoid))*sum(violation_obs_avoid.^2);
else
    const_p=[const_p, const_p_obs_avoid];
end


% total_cost=total_cost+c_dyn_lim*getCostDynLimSoftConstraints(sp, sy, basis, v_max_n, a_max_n, j_max_n, ydot_max_n);

opti.minimize(simplify(total_cost));
       

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% SOLVE! %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


all_nd=[];
for i=1:(num_max_of_obst*num_seg)
    all_nd=[all_nd [n{i};d{i}]];
end


% all_obstacle_bbox_inflated=[];
% for i=1:num_max_of_obst
%     all_obstacle_bbox_inflated=[all_obstacle_bbox_inflated obstacle_bbox_inflated{i}]; %The i-th column contains the bbox_inflated of the obstacle i
% end



pCPs=sp.getCPsAsMatrix();
yCPs=sy.getCPsAsMatrix();


% for i=1:num_samples
%     x0_feature=[1;1;1];
%     v0_feature=0.2; %Set to 0 if you want constant poistion
%     syms t real;
%     x_feature=x0_feature+v0_feature*(t-t0_n)*ones(3,1);
%     v_feature=diff(x_feature,t);
%     all_w_fe_value{i}=double(subs(x_feature,t,t_opt_n_samples(i)));
% %     all_w_velfewrtworld_value{i}=double(subs(v_feature,t,t_simpson_n(i)));
% end
% all_w_fe_value=cell2mat(all_w_fe_value);
% all_w_velfewrtworld_value=cell2mat(all_w_velfewrtworld_value);

v_max_value=1.6*ones(3,1);
a_max_value=5*ones(3,1);
j_max_value=50*ones(3,1);

alpha_value=15.0;

ydot_max_value=1.0; 
% total_time_value=10.5;
thetax_FOV_deg_value=80;
thetay_FOV_deg_value=80;
Ra_value=12.0;
y0_value=0.0;
yf_value=0.0;
ydot0_value=0.0;
ydotf_value=0.0;
b_T_c_value= [roty(90)*rotz(-90) zeros(3,1); zeros(1,3) 1];

p0_value=[-4;0.0;0.0];
v0_value=[0;0;0];
a0_value=[0;0;0];

pf_value=[4.0;0.0;0.0];
vf_value=[0;0;0];
af_value=[0;0;0];

dist_betw_planes=0.01; %See last figure of https://github.com/mit-acl/separator
norm_n=2/dist_betw_planes;

all_nd_value=[];
for j=1:floor(num_seg/2)
    all_nd_value=[all_nd_value norm_n*(1/sqrt(2))*[1; 1; 0; 2] ];
end

for j=(floor(num_seg/2)+1):num_seg
    all_nd_value=[all_nd_value norm_n*(1/sqrt(2))*[-1; 1; 0; 2] ];
end

x_lim_value=[-100;100];    y_lim_value=[-100;100];    z_lim_value=[-100;100];


tmp1=[ p0_value(1)*ones(1,sp.p-1)   linspace(p0_value(1),pf_value(1), sp.N+1-2*(sp.p-1))       pf_value(1)*ones(1,sp.p-1)
       p0_value(2)*ones(1,sp.p-1)   linspace(p0_value(2),pf_value(2), sp.N+1-2*(sp.p-1))       pf_value(2)*ones(1,sp.p-1) 
       p0_value(3)*ones(1,sp.p-1)   linspace(p0_value(3),pf_value(3), sp.N+1-2*(sp.p-1))       pf_value(3)*ones(1,sp.p-1) ];
   
tmp2=[ y0_value(1)*ones(1,sy.p-1)   linspace(y0_value(1),yf_value(1), sy.N+1-2*(sy.p-1))       yf_value(1)*ones(1,sy.p-1) ];



alpha_value = 3.53467;
tmp1=[0, 0, 0, 1.64678, 2.85231, 4.05784, 5.70462, 5.70462, 5.70462; 
      0, 0, 0, -0.378827, -1.05089, -1.71629, -2.08373, -2.08373, -2.08373; 
      0, 0, 0, 5.62017e-05, 0.00192903, 0.00290378, 0.00011499, 0.00011499, 0.00011499];
tmp2=[0, 0, 0.281832, 0.888652, 1.82877, 2.19427, 2.34944, 2.34944];



% all_obstacle_bbox_inflated_value= ones(size(all_obstacle_bbox_inflated));

par_and_init_guess= [ {createStruct('thetax_FOV_deg', thetax_FOV_deg, thetax_FOV_deg_value)},...
              {createStruct('thetay_FOV_deg', thetay_FOV_deg, thetay_FOV_deg_value)},...
              {createStruct('b_T_c', b_T_c, b_T_c_value)},...
              {createStruct('Ra', Ra, Ra_value)},...
              {createStruct('p0', p0, p0_value)},...
              {createStruct('v0', v0, v0_value)},...
              {createStruct('a0', a0, a0_value)},...
              {createStruct('pf', pf, pf_value)},...
              {createStruct('vf', vf, vf_value)},...
              {createStruct('af', af, af_value)},...
              {createStruct('y0', y0, y0_value)},...
              {createStruct('yf', yf, yf_value)},...
              {createStruct('ydot0', ydot0, ydot0_value)},...
              {createStruct('ydotf', ydotf, ydotf_value)},...
              {createStruct('v_max', v_max, v_max_value)},...
              {createStruct('a_max', a_max, a_max_value)},...
              {createStruct('j_max', j_max, j_max_value)},...
              {createStruct('ydot_max', ydot_max, ydot_max_value)},... 
              {createStruct('x_lim', x_lim, x_lim_value)},...
              {createStruct('y_lim', y_lim, y_lim_value)},...
              {createStruct('z_lim', z_lim, z_lim_value)},...
              {createStruct('alpha', alpha, alpha_value)},...
              {createStruct('c_pos_smooth', c_pos_smooth, 0.0)},...
              {createStruct('c_yaw_smooth', c_yaw_smooth, 0.0)},...
              {createStruct('c_fov', c_fov, 1.0)},...
              {createStruct('c_final_pos', c_final_pos, 2000)},...
              {createStruct('c_final_yaw', c_final_yaw, 0.0)},...
              {createStruct('c_total_time', c_total_time, 1000.0)},...
              {createStruct('all_nd', all_nd, all_nd_value)},...
              {createStruct('pCPs', pCPs, tmp1)},...
             {createStruct('yCPs', yCPs, tmp2)},...
             createCellArrayofStructsForObstacles(fitter)];   
              


[par_and_init_guess_exprs, par_and_init_guess_names, names_value]=toExprsNamesAndNamesValue(par_and_init_guess);


opts = struct;
opts.expand=true; %When this option is true, it goes WAY faster!
opts.print_time=0;
opts.ipopt.print_level=print_level; 
opts.ipopt.max_iter=500;
%opts.ipopt.print_frequency_iter=1e10;%1e10 %Big if you don't want to print all the iteratons
opts.ipopt.linear_solver=linear_solver_name;
opts.jit=jit;%If true, when I call solve(), Matlab will automatically generate a .c file, convert it to a .mex and then solve the problem using that compiled code
opts.compiler='shell';
opts.jit_options.flags='-Ofast';  %Takes ~15 seconds to generate if O0 (much more if O1,...,O3)
opts.jit_options.verbose=true;  %See example in shallow_water.cpp
% opts.ipopt.hessian_approximation='limited-memory';
% opts.ipopt.line_search_method='cg-penalty';
% opts.ipopt.accept_every_trial_step='yes';
% opts.ipopt.alpha_for_y='max';
opti.solver('ipopt',opts); %{"ipopt.hessian_approximation":"limited-memory"} 

if(pos_is_fixed==true)
    opti.subject_to([const_y]); %The control points are fixed (i.e., parameters)
else
    opti.subject_to([const_p, const_y]);
end


results_expresion={pCPs,yCPs, all_nd, total_cost, yaw_smooth_cost, pos_smooth_cost, alpha, fov_cost, final_yaw_cost, final_pos_cost}; %Note that this containts both parameters, variables, and combination of both. If they are parameters, the corresponding value will be returned
results_names={'pCPs','yCPs','all_nd','total_cost', 'yaw_smooth_cost', 'pos_smooth_cost','alpha','fov_cost','final_yaw_cost','final_pos_cost'};


%%%%


compute_cost = Function('compute_cost', par_and_init_guess_exprs ,{total_cost},...
                                        par_and_init_guess_names ,{'total_cost'});
compute_cost(names_value{:})
compute_cost=compute_cost.expand();
compute_cost.save('./casadi_generated_files/compute_cost.casadi') %The file generated is quite big


%%%%%%%%%
%%

% opti.subject_to([const_p, const_y]);
compute_dyn_limits_constraints_violation = casadi.Function('compute_dyn_limits_constraints_violation', par_and_init_guess_exprs ,{violation_dyn_limits},...
                                                           par_and_init_guess_names ,{'violation'});
tmp=compute_dyn_limits_constraints_violation(names_value{:});
compute_dyn_limits_constraints_violation=compute_dyn_limits_constraints_violation.expand();
compute_dyn_limits_constraints_violation.save('./casadi_generated_files/compute_dyn_limits_constraints_violation.casadi'); 




%%



%%%%%%%%%

%%%%%

my_func = opti.to_function('my_func', par_and_init_guess_exprs, results_expresion, par_and_init_guess_names, results_names);

if(pos_is_fixed==true)
    my_func.save('./casadi_generated_files/op_fixed_pos.casadi') %Optimization Problam. The file generated is quite big
else
    my_func.save('./casadi_generated_files/op.casadi') %Optimization Problam. The file generated is quite big
end


% opti_tmp=opti.copy;
% opti_tmp.subject_to( sp.getPosT(tf)== pf );
% my_function_tmp = opti_tmp.to_function('my_function_tmp', vars, results_vars,...
%                                                         names, results_names);
% my_function_tmp.save('./casadi_generated_files/op_force_final_pos.casadi') %The file generated is quite big
                                                    
% my_function=my_function.expand();
tic();
sol=my_func( names_value{:});
toc();
if(pos_is_fixed==false)
    statistics=get_stats(my_func); %See functions defined below
end


results_solved=[];
for i=1:numel(results_expresion)
    results_solved=[results_solved,    {createStruct(results_names{i}, results_expresion{i}, full(sol.(results_names{i})))} ];
end

full(sol.pCPs) 
full(sol.yCPs)

cprintf('Green','Total time trajec=%.2f s (alpha=%.2f) \n', full(sol.alpha*(tf_n-t0_n)), full(sol.alpha)    )


% [t_proc_total, t_wall_total]= timeInfo(my_func); %ONLY WORKS IF print_time=1


%Write param file with the characteristics of the casadi function generated
my_file=fopen('./casadi_generated_files/params_casadi.yaml','w'); %Overwrite content. This will clear its content
fprintf(my_file,'#DO NOT EDIT. Automatically generated by MATLAB\n');
fprintf(my_file,'#If you want to change a parameter, change it in main.m and run the main.m again\n');
fprintf(my_file,'deg_pos: %d\n',deg_pos);
fprintf(my_file,'deg_yaw: %d\n',deg_yaw);
fprintf(my_file,'num_seg: %d\n',num_seg);
fprintf(my_file,'num_max_of_obst: %d\n',num_max_of_obst);
fprintf(my_file,'sampler_num_samples: %d\n',sampler.num_samples);
fprintf(my_file,'fitter_num_samples: %d\n',fitter.num_samples);
fprintf(my_file,'fitter_total_time: %d\n',fitter.total_time);
fprintf(my_file,'fitter_num_seg: %d\n',fitter.num_seg);
fprintf(my_file,'fitter_deg_pos: %d\n',fitter.deg_pos);
fprintf(my_file,'num_of_yaw_per_layer: %d\n',num_of_yaw_per_layer); % except in the initial layer, that has only one value
fprintf(my_file,'basis: "%s"\n',basis);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%% FUNCTION TO GENERATE VISIBILITY AT EACH POINT  %%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% fitter.bs=MyCasadiClampedUniformSpline(0,1,deg_obstacle,dim_obstacle,num_seg,fitter.ctrl_pts, false);

yaw_samples=MX.sym('yaw_samples',1,num_of_yaw_per_layer); 

all_is_in_FOV_for_different_yaw=[];
for yaw_sample_i=yaw_samples
    all_is_in_FOV_for_different_yaw=  [all_is_in_FOV_for_different_yaw;
                                        substitute(all_is_in_FOV_smooth, yaw, yaw_sample_i)];  
end
all_is_in_FOV_for_different_yaw=all_is_in_FOV_for_different_yaw'; % Each row will be a layer. Each column will have yaw=constat

pCPs=sp.getCPsAsMatrix();


%%



par_and_init_guess= [ {createStruct('pCPs', pCPs, full(sol.pCPs))},...
                      {createStruct('alpha', alpha, alpha_value)},...
                      {createStruct('thetax_FOV_deg', thetax_FOV_deg, thetax_FOV_deg_value)},...
                      {createStruct('thetay_FOV_deg', thetay_FOV_deg, thetay_FOV_deg_value)},...
                      {createStruct('b_T_c', b_T_c, b_T_c_value)},...
                      {createStruct('yaw_samples', yaw_samples, linspace(0,2*pi,numel(yaw_samples)))},...
                      createCellArrayofStructsForObstacles(fitter)];   

[par_and_init_guess_exprs, par_and_init_guess_names, names_value]=toExprsNamesAndNamesValue(par_and_init_guess);
                  

g = Function('g', par_and_init_guess_exprs ,{all_is_in_FOV_for_different_yaw},...
                  par_and_init_guess_names ,{'result'});
g=g.expand();

g.save('./casadi_generated_files/visibility.casadi') %The file generated is quite big

g_result=g(names_value{:});

full(g_result.result);


%%%%%%%%%%%%%%%%%%%%%%%%%%% Store solution! %%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sp_cpoints_var=sp.getCPsAsMatrix();
sp.updateCPsWithSolution(full(sol.pCPs))

sy_cpoints_var=sy.getCPsAsMatrix();
sy.updateCPsWithSolution(full(sol.yCPs))



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%% PLOTTING! %%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if(make_plots)

import casadi.*
% alpha_value=convertMX2Matlab(substitute(alpha,alpha, total_time_value));

alpha_sol=full(sol.alpha);

v_max_n_value= v_max_value*alpha_sol;
a_max_n_value= a_max_value*(alpha_sol^2);
j_max_n_value= j_max_value*(alpha_sol^3);

ydot_max_n_value= ydot_max_value*alpha_sol;

sp.plotPosVelAccelJerk(v_max_n_value, a_max_n_value, j_max_n_value)
% sp.plotPosVelAccelJerkFiniteDifferences();
sy.plotPosVelAccelJerk(ydot_max_n_value)
% sy.plotPosVelAccelJerkFiniteDifferences();

sp.plotPos3D();
plotSphere( sp.getPosT(t0_n),0.2,'b'); plotSphere( sp.getPosT(tf_n),0.2,'r'); 

view([280,15]); axis equal
% 
disp("Plotting")



for t_nobs=t_opt_n_samples %t0:0.3:tf  
    
    w_t_b = sp.getPosT(t_nobs);
%     accel = sp.getAccelT(t_i);% sol.value(A{n})*Tau_i;
    
    accel_n = sp.getAccelT(t_nobs);
    accel = accel_n/(alpha_sol^2);
    
    yaw = sy.getPosT(t_nobs);
%         psiT=sol.value(Psi{n})*Tau_i;

    qabc=qabcFromAccel(accel, 9.81);

    qpsi=[cos(yaw/2), 0, 0, sin(yaw/2)]; %Note that qpsi has norm=1
    q=multquat(qabc,qpsi); %Note that q is guaranteed to have norm=1

    w_R_b=toRotMat(q);
    w_T_b=[w_R_b w_t_b; 0 0 0 1];
    plotAxesArrowsT(0.5,w_T_b)
    
    %Plot the FOV cone
    w_T_c=w_T_b*b_T_c_value;
    position=w_T_c(1:3,4);
    direction=w_T_c(1:3,3);
    length=1;
    plotCone(position,direction,thetax_FOV_deg_value,length); 

end

for i=1:num_max_of_obst
    tmp=substituteWithSolution(obst{1}.centers, results_solved, par_and_init_guess);
    for ii=1:size(tmp,2)
        plotSphere(tmp(:,ii),0.2,'g');
    end
end


grid on; xlabel('x'); ylabel('y'); zlabel('z'); camlight; lightangle(gca,45,0)

syms x y z real
all_nd_solved=full(sol.all_nd);
cte_visualization=repmat(vecnorm(all_nd_solved),4,1); %Does not changes the planes
all_nd_solved=all_nd_solved./cte_visualization;

for i=1:size(all_nd_solved,2)
    fimplicit3(all_nd_solved(:,i)'*[x;y;z;1],[-4 4 -4 4 -2 2], 'MeshDensity',2, 'FaceAlpha',0.6) 
end

view(-91,90)


all_fov_costs_evaluated=substituteWithSolution(all_fov_costs, results_solved, par_and_init_guess);

figure;
plot(all_fov_costs_evaluated,'-o'); title('Fov cost. $>$0 means not in FOV')



% figure; hold on; import casadi.*
% 
% all_s_logged=[];
% for i=1:num_samples_simpson
%     t_obs=s_logged{i};
%     
%     %Substitute all the params
%     for ii=1:numel(par_and_init_guess)
%         t_obs=substitute(t_obs,par_and_init_guess{ii}.param, par_and_init_guess{ii}.value);
%     end
%     
% %   sol.value(tmp)
% 
%     %Substitute the solution
%     t_obs=substitute(t_obs, sp_cpoints_var, sp.getCPsAsMatrix());
%     t_obs=substitute(t_obs, sy_cpoints_var, sy.getCPsAsMatrix());
%     
%     all_s_logged=[all_s_logged convertMX2Matlab(t_obs)];
% end
% 
% % plot(t_simpson, all_s_logged,'o');legend('u','v');
% % plot(all_s_logged(1,:), all_s_logged(2,:),'o');
% x=all_s_logged(1,:); y=all_s_logged(2,:);
% scatter(x,y,60,1:numel(x),'Filled')
% title('Image projection of the feature');
% xlim([-max(abs(x)),max(abs(x))]); ylim([-max(abs(y)),max(abs(y))]); yline(0.0,'--');xline(0.0,'--')
% %  set(gca, 'XAxisLocation', 'origin', 'YAxisLocation', 'origin')

end
%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%    FUNCTION TO FIT A SPLINE TO YAW SAMPLES     %%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sy_tmp=MyClampedUniformSpline(t0_n,tf_n,deg_yaw, dim_yaw, num_seg, opti);  %creating another object to not mess up with sy

all_yaw=MX.sym('all_yaw',1,numel(t_opt_n_samples));
cost_function=0;
for i=1:numel(t_opt_n_samples)
    cost_function = cost_function + (sy_tmp.getPosT(t_opt_n_samples(i))-all_yaw(i))^2; 
end

lambda1=MX.sym('lambda1',1,1);
lambda2=MX.sym('lambda2',1,1);
lambda3=MX.sym('lambda3',1,1);

%Note that y0 \equiv all_yaw(1)
c1= sy_tmp.getPosT(t0_n) - all_yaw(1); %==0
c2= sy_tmp.getVelT(t0_n) - ydot0_n; %==0
c3= sy_tmp.getVelT(tf_n) - ydotf_n; %==0

lagrangian = cost_function  +  lambda1*c1 + lambda2*c2 + lambda3*c3;

variables=[sy_tmp.getCPsAsMatrix() lambda1 lambda2  lambda3];

kkt_eqs=jacobian(lagrangian, variables)'; %I want kkt=[0 0 ... 0]'

%Obtain A and b
b=-casadi.substitute(kkt_eqs, variables, zeros(size(variables))); %Note the - sign
A=jacobian(kkt_eqs, variables);

solution=A\b;  %Solve the system of equations

f= Function('f', {all_yaw, alpha, ydot0, ydotf }, {solution(1:end-3)}, ...
                 {'all_yaw', 'alpha', 'ydot0', 'ydotf'}, {'result'} );
% f=f.expand();
all_yaw_value=linspace(0,pi,numel(t_opt_n_samples));


solution=f(all_yaw_value, alpha_value, ydot0_value, ydotf_value);
sy_tmp=MyClampedUniformSpline(t0_n,tf_n,deg_yaw, dim_yaw, num_seg, opti);  %creating another object to not mess up with sy
sy_tmp.updateCPsWithSolution(full(solution)');
sy_tmp.plotPosVelAccelJerk();
subplot(4,1,1); hold on;
plot(t_opt_n_samples, all_yaw_value, 'o')


f.save('./casadi_generated_files/fit_yaw.casadi') 


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%    FUNCTION TO FIT A SPLINE TO POSITION SAMPLES     %%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%samples should be sampled uniformly, including first and last point
%The total number of samples is num_samples

%If you find the error "evaluation failed" --> increase num_samples or
%reduce deg_pos or num_seg

%%

samples=MX.sym('samples',fitter.dim_pos,fitter.num_samples);
cost_function=0;
i=1;
for ti=linspace(fitter.bs.knots(1), fitter.bs.knots(end), fitter.num_samples)
    dist=(fitter.bs.getPosT(ti)-samples(:,i));      cost_function = cost_function + dist'*dist; 
    i=i+1;
end

lagrangian = cost_function;

fitter_bs_CPs=fitter.bs.getCPsAsMatrix();
variables=[fitter_bs_CPs ]; 

kkt_eqs=jacobian(lagrangian, variables)'; %I want kkt=[0 0 ... 0]'

%Obtain A and b
b=-casadi.substitute(kkt_eqs, variables, zeros(size(variables))); %Note the - sign
A=jacobian(kkt_eqs, variables);

solution=A\b;  %Solve the system of equations

f= Function('f', {samples }, {reshape(solution(1:end), fitter.dim_pos,-1)}, ...
                 {'samples'}, {'result'} );
% f=f.expand();

t=linspace(0, 2, fitter.num_samples);

samples_value=[sin(t)+2*sin(2*t);
               cos(t)-2*cos(2*t);
               -sin(3*t)];


solution=f(samples_value);

%%

cost_function=substitute(cost_function, fitter.bs.getCPsAsMatrix, full(solution));
cost_function=substitute(cost_function, samples, samples_value);
convertMX2Matlab(cost_function)

% sp_tmp=MyClampedUniformSpline(t0_n,tf_n,deg_pos, dim_pos, num_seg, opti);  %creating another object to not mess up with sy
fitter.bs.updateCPsWithSolution(full(solution));


% sp_tmp.plotPosVelAccelJerk();

fitter.bs.plotPos3D();
scatter3(samples_value(1,:), samples_value(2,:), samples_value(3,:))

f.save('./casadi_generated_files/fit3d.casadi') 



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%% OBTAIN CLOSED-FORM SOLUTION FOR YAW GIVEN POSITION %%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

sp=MyClampedUniformSpline(t0_n,tf_n,deg_pos, dim_pos, num_seg, opti); %spline position.
% sy=MyClampedUniformSpline(t0_n,tf_n,deg_yaw, dim_yaw, num_seg, opti); %spline yaw.

n_samples=50;

all_t_n=linspace(t0_n,tf_n,n_samples);


all_w_fevar=MX.sym('all_w_fevar',3,n_samples);

i_star=1; %For now focus on the first obstacle

all_yaw=[];
dataPoints={};
i=1;
for t=all_t_n
    
    pos=sp.getPosT(t);
    pos_feature=fitter.bs_casadi{i_star}.getPosT(t*alpha/(fitter.total_time    ));

    a_n = sp.getAccelT(t);
    a = a_n/(alpha^2);

    ee=pos_feature-pos;
    xi=a+[0 0 9.81]';

    r0_star=(ee*norm(xi)^2 - (ee'*xi)*xi);
    r0_star=r0_star/norm(r0_star);
    
    tmp=pos+r0_star;

    qabc=qabcFromAccel(a, 9.81);
    Rabc=toRotMat(qabc);
    w_Tabc_b0y=[Rabc pos; 0 0 0 1]; %The frame "b0y" stands for "body zero yaw", and has yaw=0
    
    b0y_r0star=invPose(w_Tabc_b0y)*[tmp;1]; %express the vector in the frame "b0y" 
    b0y_r0star=b0y_r0star(1:3); 
%     assert(abs(b0y_r0star(3))<0.0001)
    
    dataPoints{end+1}=b0y_r0star(1:2)';
    all_yaw=[all_yaw atan2(b0y_r0star(2),b0y_r0star(1))]; %compute the yaw angle 
    
    i=i+1;
end

tmp=[y0 all_yaw]; %We append y0 to make sure that the first element of all_yaw_corrected is not more than 2pi from y0
tmp_corrected=shiftToEnsureNoMoreThan2Pi(tmp);
all_yaw_corrected=tmp_corrected(2:end); 
% all_yaw_corrected=shiftToEnsureNoMoreThan2Pi(all_yaw); 

sy=MyClampedUniformSpline(t0_n,tf_n,deg_yaw, dim_yaw, num_seg, opti); 

cost_function=0;
for i=1:numel(all_t_n)
    cost_function = cost_function + (sy.getPosT(all_t_n(i))-all_yaw_corrected(i))^2; 
end

lambda1=MX.sym('lambda1',1,1);
lambda2=MX.sym('lambda2',1,1);
lambda3=MX.sym('lambda3',1,1);

%Note that y0 \equiv all_yaw(1)
c1= sy.getPosT(t0_n) - y0; %==0
c2= sy.getVelT(t0_n) - ydot0_n; %==0
c3= sy.getVelT(tf_n) - ydotf_n; %==0

lagrangian = cost_function  +  lambda1*c1 + lambda2*c2 + lambda3*c3;

variables=[sy.getCPsAsMatrix() lambda1 lambda2  lambda3];

kkt_eqs=jacobian(lagrangian, variables)'; %I want kkt=[0 0 ... 0]'

%Obtain A and b
b=-casadi.substitute(kkt_eqs, variables, zeros(size(variables))); %Note the - sign
A=jacobian(kkt_eqs, variables);

%solution=A\b;  %Option 1
solution=solve(A,b, 'symbolicqr'); %Option 2, allows for expand(), see https://groups.google.com/g/casadi-users/c/kOYv6lvNgEI/m/UiAYsdJEBAAJ

pCPs=sp.getCPsAsMatrix();
% pCPs_feature=fitter.ctrl_pts{i_star}.CPoints; 
pCPs_feature=fitter.bs_casadi{i_star}.CPoints;
% yCPs=sy.getCPsAsMatrix();

f= Function('f', {pCPs, pCPs_feature, alpha, y0,ydot0, ydotf }, {solution(1:end-3),all_yaw_corrected}, ...
                 {'pCPs', 'pCPs_feature', 'alpha', 'y0','ydot0', 'ydotf'}, {'solution','all_yaw_corrected'} );

f=f.expand(); %

f.save('./casadi_generated_files/get_optimal_yaw_for_fixed_pos.casadi') 

% pCPs_value=[   -4.0000   -4.0000   8    5    3   2     -4 -4 -4;
%          -2         0         0   -5   -7   -8   -9 -9 -9;
%          0         2         -2    7    0.0052    3    0.0052 0.0052 0.0052];


pCPs_value=[[0, 0, 0, 0.601408, 2.57406, 4.70471, 5.96806, 5.96806, 5.96806];
 [0, 0, 0, -0.0954786, -0.261755, -0.312647, -0.270762, -0.270762, -0.270762]; 
 [1, 1, 1, 1.14378, 1.07827, 1.01892, 1.0935, 1.0935, 1.0935]];
% pCPs_feature_value=([1 -2 3]').*ones(3,fitter.bs.num_cpoints);

pCPs_feature_value=[[4.21462, 4.00643, 3.40667, 2.8736, 3.28795, 4.29628, 4.95785, 4.71115, 4.19066, 3.9898]; 
 [0.298978, 0.559347, 0.845803, 0.313731, -0.44788, -0.481992, 0.313604, 1.05783, 0.922028, 0.696952]; 
 [-0.167948, -0.601469, -0.582628, 1.6641, 1.48017, -0.797825, -0.310188, 1.86143, 1.43191, 0.92248]];

alpha_value=5.93368;
y0_value=6.08049;
ydot0_value=-0.103688;
ydotf_value=0.0;


disp("Calling function")
tic
result=f('pCPs', pCPs_value, 'pCPs_feature', pCPs_feature_value, 'alpha', alpha_value, ...
        'y0', y0_value,'ydot0', ydot0_value, 'ydotf', ydotf_value);
toc
disp("Function called")

sy.updateCPsWithSolution(full(result.solution)')
figure
sy.plotPos();
subplot(1,1,1); hold on;
% plot(all_t_n,full(result.all_yaw),'o')
plot(all_t_n,full(result.all_yaw_corrected),'o')

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Functions

         
 function result=createCellArrayofStructsForObstacles(fitter)
         
     num_obs=size(fitter.bbox_inflated,2);

     result=[];
     
     for i=1:num_obs
        name_crtl_pts=['obs_', num2str(i-1), '_ctrl_pts'];  %Note that we use i-1 here because it will be called from C++
        name_bbox_inflated=['obs_', num2str(i-1), '_bbox_inflated'];          %Note that we use i-1 here because it will be called from C++

        crtl_pts_value=zeros(size(fitter.bs_casadi{i}.CPoints));

        result=[result,...
                {createStruct(name_crtl_pts,   fitter.ctrl_pts{i} , crtl_pts_value)},...
                {createStruct(name_bbox_inflated, fitter.bbox_inflated{i} ,  [1;1;1]  )}];

    end
         
 end

function [par_and_init_guess_exprs, par_and_init_guess_names, names_value]=toExprsNamesAndNamesValue(par_and_init_guess)

par_and_init_guess_exprs=[]; %expressions
par_and_init_guess_names=[]; %guesses
names_value={};
for i=1:numel(par_and_init_guess)
    par_and_init_guess_exprs=[par_and_init_guess_exprs {par_and_init_guess{i}.expression}];
    par_and_init_guess_names=[par_and_init_guess_names {par_and_init_guess{i}.name}];

    names_value{end+1}=par_and_init_guess{i}.name;
    names_value{end+1}=double2DM(par_and_init_guess{i}.value); 

end

end


function result=substituteWithSolution(expression, all_var_solved, all_params_and_init_guesses)

  import casadi.*
    result=zeros(size(expression));
    for i=1:size(expression,1)
        for j=1:size(expression,2)
            
                tmp=expression(i,j);
                
                %Substitute FIRST the solution [note that this one needs to be first because in all_params_and_init_guesses we have also the initial guesses, which we don't want to use]
                for ii=1:numel(all_var_solved)
                    if(isPureParamOrVariable(all_var_solved{ii}.expression)==false) 
                        continue;
                    end
                    tmp=substitute(tmp,all_var_solved{ii}.expression, all_var_solved{ii}.value);
                end
                
                 %And THEN substitute the parameters
                for ii=1:numel(all_params_and_init_guesses)
                    tmp=substitute(tmp,all_params_and_init_guesses{ii}.expression, all_params_and_init_guesses{ii}.value);
                end
            
            result(i,j)=convertMX2Matlab(tmp);
        end
    end


end

%This checks whether it is a pure variable/parameter in the optimization (returns true) or not (returns false). Note that with an expression that is a combination of several double/variables/parameters will return false
function result=isPureParamOrVariable(expression)
    result=expression.is_valid_input();
end

%ONLY WORKS IF print_time=1
function [t_proc_total, t_wall_total]= timeInfo(my_func)
    tmp=get_stats(my_func);
    
    %%See https://github.com/casadi/casadi/wiki/FAQ:-is-the-bottleneck-of-my-optimization-in-CasADi-function-evaluations-or-in-the-solver%3F
    
    %This is the time spent evaluating the functions
    t_casadi=  (tmp.t_wall_nlp_f+tmp.t_wall_nlp_g+tmp.t_wall_nlp_grad+tmp.t_wall_nlp_grad_f+tmp.t_wall_nlp_hess_l+tmp.t_wall_nlp_jac_g);
    
    t_ipopt= tmp.t_wall_total-t_casadi;

    cprintf('key','Total time=%.2f ms [Casadi=%.2f%%, IPOPT=%.2f%%]\n',tmp.t_wall_total*1000, 100*t_casadi/tmp.t_wall_total, 100*t_ipopt/tmp.t_wall_total    )
    
    
    
    t_wall_total=tmp.t_wall_total;
    t_proc_total=tmp.t_proc_total;    
    
end

%Not fully implemented yet
% function cost=getCostDynLimSoftConstraints( sp, sy, basis, v_max_n, a_max_n, j_max_n, ydot_max_n)
% 
%     [~, slacks_vel_p] =  sp.getMaxVelConstraints(basis, v_max_n);
%     [~, slacks_accel_p] =sp.getMaxAccelConstraints(basis, a_max_n);
%     [~, slacks_jerk_p] = sp.getMaxJerkConstraints(basis, j_max_n);
%     [~, slacks_vel_y] =  sy.getMaxVelConstraints(basis, ydot_max_n);   %Max vel constraints (yaw)
% 
%     all_slacks=[slacks_vel_p slacks_vel_p, slacks_accel_p, slacks_vel_y];%[slacks_vel_p, slacks_accel_p, slacks_jerk_p, slacks_vel_y];
% 
%     cost=0.0;
%     for i=1:length(all_slacks)
%             cost=cost+max(0,all_slacks{i})^3;% Constraint is slack<=0
%     end
% 
% end

function [const_p_dyn_limits,const_y_dyn_limits]=addDynLimConstraints(const_p_dyn_limits,const_y_dyn_limits, sp, sy, basis, v_max_n, a_max_n, j_max_n, ydot_max_n)

     const_p_dyn_limits=[const_p_dyn_limits sp.getMaxVelConstraints(basis, v_max_n)];      %Max vel constraints (position)
     const_p_dyn_limits=[const_p_dyn_limits sp.getMaxAccelConstraints(basis, a_max_n)];    %Max accel constraints (position)
     const_p_dyn_limits=[const_p_dyn_limits sp.getMaxJerkConstraints(basis, j_max_n)];     %Max jerk constraints (position)
     const_y_dyn_limits=[const_y_dyn_limits sy.getMaxVelConstraints(basis, ydot_max_n)];   %Max vel constraints (yaw)

end

%Taken from https://gist.github.com/jgillis/9d12df1994b6fea08eddd0a3f0b0737f
%See discussion at https://groups.google.com/g/casadi-users/c/1061E0eVAXM/m/dFHpw1CQBgAJ
function [stats] = get_stats(f)
  dep = 0;
  % Loop over the algorithm
  for k=0:f.n_instructions()-1
%      fprintf("Trying with k= %d\n", k)
    if f.instruction_id(k)==casadi.OP_CALL
      fprintf("Found k= %d\n", k)
      d = f.instruction_MX(k).which_function();
      if d.name()=='solver'
        my_file=fopen('./casadi_generated_files/index_instruction.txt','w'); %Overwrite content
        fprintf(my_file,'%d\n',k);
        dep = d;
        break
      end
    end
  end
  if dep==0
    stats = struct;
  else
    stats = dep.stats(1);
  end
end

function a=createStruct(name,expression,value)
    a.name=name;
    a.expression=expression;
    a.value=value;
end

function result=mySig(gamma,x)
    result=(1/(1+exp(-gamma*x)));
end
%%

        % See https://en.wikipedia.org/wiki/Cone#Equation_form:~:text=In%20implicit%20form%2C%20the%20same%20solid%20is%20defined%20by%20the%20inequalities
    %%%%%%%%%%%%%%%%%%%
%     %FOV version 1 (cone):
%     % See https://en.wikipedia.org/wiki/Cone#Equation_form:~:text=In%20implicit%20form%2C%20the%20same%20solid%20is%20defined%20by%20the%20inequalities
%       gamma1=100; gamma2=100;
%     xx{j}=c_P(1); yy{j}=c_P(2); zz{j}=c_P(3);
%     x=c_P(1);y=c_P(2); z=c_P(3);
%     is_in_FOV1{j}=-((x^2+y^2)*(cos(theta_half_FOV_deg*pi/180.0))^2 -(z^2)*(sin(theta_half_FOV_deg*pi/180.0))^2); %(if this quantity is >=0)
%     is_in_FOV2{j}=c_P(3); %(and this quantity is >=0)
%     isInFOV_smooth=  (   1/(1+exp(-gamma1*is_in_FOV1{j}))  )*(   1/(1+exp(-gamma2*is_in_FOV2{j}))  );
%     target_isInFOV{j}=isInFOV_smooth; %/(0.1+f_vel_im{n})
%     
%     %Costs (all of them following the convention of "minimize" )
%     f_vel_im{j}=(s_dot'*s_dot);
%     f_dist_im{j}=(s'*s); %I wanna minimize the integral of this funcion. Approx. using symp. Rule
%     f_vel_isInFOV_im{j}=-(target_isInFOV{j}) /(offset_vel+f_vel_im{j});
%       %End of one possible version
      %%%%%%%%%%%%%%%%%%%
      
      %FOV version 2: (the four planes of the FOV (i.e. a pyramid) + sigmoid to smooth)
      %See also Mathematica notebook
%       gamma=30;
%       tthx=tan(thetax_half_FOV_rad);
%       tthy=tan(thetay_half_FOV_rad);
%       v0h=[0.0, 0.0, 0.0, 1.0]';     %Vertex of the pyramid
%       v1h=[-tthx, -tthy, 1.0, 1.0]'; %Point in the base of the pyramid
%       v2h=[-tthx, tthy, 1.0, 1.0]';  %Point in the base of the pyramid
%       v3h=[tthx, tthy, 1.0, 1.0]';   %Point in the base of the pyramid
%       v4h=[tthx, -tthy, 1.0, 1.0]';  %Point in the base of the pyramid
%       x=c_P(1);y=c_P(2); z=c_P(3);
%       xyzh=[x, y, z, 1.0]';
%       dA21=computeDet([xyzh'; v0h'; v2h'; v1h'] );%This has to be >=0
%       dA32=computeDet([xyzh'; v0h'; v3h'; v2h'] );%This has to be >=0
%       dA43=computeDet([xyzh'; v0h'; v4h'; v3h'] );%This has to be >=0
%       dA14=computeDet([xyzh'; v0h'; v1h'; v4h'] );%This has to be >=0
%       isInFOV_smooth=(mySig(gamma, dA21)*mySig(gamma, dA32)*mySig(gamma, dA43)*mySig(gamma, dA14));
      
      
%%%%%%%%%%%%%%%%%%


    %     %%%%%%%%%%%%%%%%%%%
      %FOV version 3: [Squicular cone]
%     gamma1=0.6; %If too big, the warning "solver:nlp_grad_f failed: NaN detected for output grad_f_x" will appear
%     gamma2=1.0;
%     tthx2=(tan(thetax_half_FOV_rad))^2;
%     tthy2=(tan(thetay_half_FOV_rad))^2;
%     
%     x=c_P(1);y=c_P(2); z=c_P(3);  ss=0.95;
% %%%     is_in_FOV1=-(    (x^2)*(z^2)/tthx2  +  (y^2)*(z^2)/tthy2   -(ss^2)*(x^2)*(y^2) -(z^4)     ); %(if this quantity is >=0). See https://en.wikipedia.org/wiki/Squircle, Note that  a^2=tan^2(theta_half_x)     b^2=tan^2(theta_half_y)   
%     is_in_FOV1= -(    (x^4)/tthx2  +  (y^4)/tthy2   -(z^4)     ); %(if this quantity is >=0). See https://en.wikipedia.org/wiki/Squircle, , Note that  a^2=tan^2(theta_half_x)     b^2=tan^2(theta_half_y)   
%     is_in_FOV2=z; %(and this quantity is >=0) 
%     isInFOV_smooth=  (   1/(1+exp(-gamma1*is_in_FOV1))  )*(   1/(1+exp(-gamma2*is_in_FOV2))  );
%     %%%%%%%%%%%%%%%%%%%



%%
% %% EXAMPLE OF CALLING THE PROBLEM DIRECTLY (WITHOUT FUNCTION)
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%% INITIAL GUESSES  %%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% for i=1:sp.num_cpoints
%     opti.set_initial(sp.CPoints{i}, zeros(3,1)); %Control points
% end
% 
% for i=1:sy.num_cpoints
%     opti.set_initial(sy.CPoints{i}, zeros(1,1)); %Control points
% end
%                     
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%% ASSIGNMENT for the parameters %%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% opti.set_value(c_pos_smooth, 0.0);
% opti.set_value(c_yaw_smooth, 0.0);
% opti.set_value(c_fov, 1.0);
% opti.set_value(c_final_pos, 100);
% 
% opti.set_value(theta_FOV_deg, 80);
% 
% opti.set_value(p0, [-4;0;0]);
% opti.set_value(v0, [0;0;0]);
% opti.set_value(a0, [0;0;0]);
% 
% opti.set_value(pf, [4;0;0]);
% opti.set_value(vf, [0;0;0]);
% opti.set_value(af, [0;0;0]);
% 
% opti.set_value(y0, 0);
% opti.set_value(ydot0, 0);
% 
% for i=1:(num_max_of_obst*num_seg)
%     opti.set_value(n{i}, rand(3,1));
%     opti.set_value(d{i}, rand(1,1));
% end
% 
% %Positions of the feature
% for i=1:num_samples_simpson
%     opti.set_value(w_fe{i}, [1 1 1]');
% end
% 
% %Max vel and accel
% opti.set_value(v_max, 1.6*ones(3,1));
% opti.set_value(a_max, 5*ones(3,1));
% 
% opti.set_value(total_time, 10.5);
% 
% %%%%%%%%%%%%%%%%%%%%%%%%%%% SOLVE!
% sol = opti.solve();
% sp.updateCPsWithSolution(sol)
% sy.updateCPsWithSolution(sol)
% 
% 
% figure; hold on;
% semilogy(sol.stats.iterations.inf_du)
% semilogy(sol.stats.iterations.inf_pr)


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% OLD CODE %%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% In case you wanna generate c code
% opts_nlpsol.x=opti.x;
% opts_nlpsol.f=opti.f;
% opts_nlpsol.g=opti.g;
% opts_nlpsol.p=opti.p;
% solver = nlpsol('my_solver', 'ipopt', opts_nlpsol);
% solver.generate_dependencies('example.c')
%%% Other stuff
% arg = opti.advanced.arg() % get nlpsol args
% solution = solver(lbg=arg['lbg'], ubg=arg['ubg'], lam_g0=arg['lam_g0'], p=arg['p'], x0=arg['x0']);

% disp ("SOLUTION 1")
% disp("Translation")
% for i=1:sp.num_cpoints
%     sol.value(sp.CPoints{tm(i)})'
% %      opti.set_initial(sp.CPoints{tm(i)},sol.value(sp.CPoints{tm(i)})); %Control points
% end



% 
% disp("Yaw")
% for i=1:sy.num_cpoints
%     sol.value(sy.CPoints{tm(i)});
%     opti.set_initial(sy.CPoints{tm(i)},sol.value(sy.CPoints{tm(i)})); %Control points
% end
% 
% % https://stackoverflow.com/questions/43104254/ipopt-solution-is-not-optimal
% opts = struct;
% opts.ipopt.warm_start_init_point = 'yes';
% opts.ipopt.warm_start_bound_push=1e-9;
% opts.ipopt.warm_start_bound_frac=1e-9;
% opts.ipopt.warm_start_slack_bound_frac=1e-9;
% opts.ipopt.warm_start_slack_bound_push=1e-9;
% opts.ipopt.warm_start_mult_bound_push=1e-9;
% opti.solver('ipopt',opts);
% 
% sol = opti.solve();
% 
% sp.updateCPsWithSolution(sol)
% sy.updateCPsWithSolution(sol)
% 
% disp ("SOLUTION 2")
% disp("Translation")
% sp.printCPs();
% disp("Yaw")
% sy.printCPs();



% 
% simpson_index=1;
% for j=1:sp.num_seg 
%      for u_i=u_simpson{j}
%          
%         tmp=s_logged{j};
%         
%         %Substitute all the params
%         for ii=1:numel(all_params)
%             tmp=substitute(tmp,all_params{ii}.param, all_params{ii}.value);
%         end
%         
%         %Substitute the solution
%         tmp=substitute(tmp, sp_cpoints_var, sp.getCPsAsMatrix());
%         tmp=substitute(tmp, sy_cpoints_var, sy.getCPsAsMatrix());
%         
%         %Substitute ui
%         tmp=substitute(tmp, u, u_i);
%         tmp=substitute(tmp, u, u_i);
%          
% %         tmp=substitute(     substitute(s_logged{j},u,u_i)    ,w_fevar, w_fe{simpson_index}  );
% %         
% % %         
% % %         sp_cpoints_var=sp.getCPsAsMatrix();
% % % sy_cpoints_var=sy.getCPsAsMatrix();
% %         
% %         tmp=substitute(tmp, sp_cpoints_var, sp.getCPsAsMatrix());
% %         
% %         tmp=substitute(tmp, sy_cpoints_var, sy.getCPsAsMatrix());
% %         tmp=substitute(tmp,w_velfewrtworldvar, w_velfewrtworld{simpson_index});
% %         
% %         for (ii=1:size(all_params_value,2))
% %          tmp=substitute(tmp,all_params{ii}, all_params_value{ii})
% %         end
% %         
% %         simpson_index=simpson_index+1;
%      end
% end

% for j=1:sp.num_seg 
%     
%     for index_obs=1:num_max_of_obst
%         init_int=min(sp.timeSpanOfInterval(j)); 
%         end_int=max(sp.timeSpanOfInterval(j)); 
%         vertexes=getVertexesMovingObstacle(init_int,end_int); %This call should depend on the obstacle itself
% 
%         x=vertexes(1,:);     y=vertexes(2,:);    z=vertexes(3,:);
% 
%         [k1,av1] = convhull(x,y,z);
%         trisurf(k1,x,y,z,'FaceColor','cyan')
%     end
%     
% end



% figure; hold on; 
% subplot(3,1,1);hold on; title('isInFOV()')
% subplot(3,1,2); hold on; title('Cost v')
% subplot(3,1,3); hold on; title('Cost -isInFOV()/(e + v)')
% simpson_index=1;
% for j=1:sp.num_seg
%     for u_i=u_simpson{j}
%         t_i=sp.u2t(u_i,j);
%         subplot(3,1,1);    ylim([0,1]);        
%         stem(t_i, sol.value(substitute(     substitute(target_isInFOV{j},u,u_i)    ,w_fevar, w_fe{simpson_index}  )),'filled','r')
%         subplot(3,1,2);
%         stem(t_i, sol.value(substitute(     substitute(f_vel_im{j},u,u_i)             ,w_fevar, w_fe{simpson_index}  )),'filled','r')
%         subplot(3,1,3);
%         stem(t_i, sol.value(substitute(     substitute(f_vel_isInFOV_im{j},u,u_i)     ,w_fevar, w_fe{simpson_index}  )),'filled','r') 
%         simpson_index=simpson_index+1;
%     end
% end
