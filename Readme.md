# Deep-PANTHER: Learning-Based Perception-Aware Trajectory Planner in Dynamic Environments #


[![Deep-PANTHER: Learning-Based Perception-Aware Trajectory Planner in Dynamic Environments](./panther/imgs/deep_panther.gif)](https://www.youtube.com/watch?v=53GBjP1jFW8 "Deep-PANTHER: Learning-Based Perception-Aware Trajectory Planner in Dynamic Environments")  


## Citation

When using Deep-PANTHER, please cite [Deep-PANTHER: Learning-Based Perception-Aware Trajectory Planner in Dynamic Environments](https://arxiv.org/abs/2209.01268) ([pdf](https://arxiv.org/pdf/2209.01268.pdf) and [video](https://www.youtube.com/watch?v=53GBjP1jFW8)):

```bibtex
@article{tordesillas2022deep,
  title={Deep-PANTHER: Learning-Based Perception-Aware Trajectory Planner in Dynamic Environments},
  author={Tordesillas, Jesus and How, Jonathan P},
  journal={arXiv preprint arXiv:2209.01268},
  year={2022}
}
```

## General Setup

DeepPANTHER has been tested with Ubuntu 20.04/ROS Noetic. Other Ubuntu/ROS version may need some minor modifications, feel free to [create an issue](https://github.com/mit-acl/panther/issues) if you have any problems.

The instructions below assume that you have ROS Noetic and MATLAB installed on your Linux machine. For Matlab you will only need the `Symbolic Math Toolbox` and the `Phased Array System Toolbox` installed. 

### <ins>Dependencies<ins>


#### CasADi and IPOPT

The steps below are partly taken from [here](https://github.com/casadi/casadi/wiki/InstallationLinux#installation-on-linux))

==============================  CASADI  =========================

First install IPOPT following these steps:

```bash
sudo apt-get install gcc g++ gfortran git cmake liblapack-dev pkg-config --install-recommends
sudo apt-get install coinor-libipopt1v5 coinor-libipopt-dev
```

Then install CasADi:

```bash
sudo apt-get remove swig swig3.0 swig4.0 #If you don't do this, the compilation of casadi may fail with the error "swig error : Unrecognized option -matlab"
mkdir ~/installations && cd ~/installations
git clone https://github.com/jaeandersson/swig
cd swig
git checkout -b matlab-customdoc origin/matlab-customdoc        
sh autogen.sh
sudo apt-get install gcc-7 g++-7 bison byacc
./configure CXX=g++-7 CC=gcc-7            
make
sudo make install


cd ~/installations && mkdir casadi && cd casadi
git clone https://github.com/casadi/casadi
cd casadi 
#cd build && make clean && cd .. && rm -rf build #Only if you want to clean any previous installation/compilation 
mkdir build && cd build
cmake . -DCMAKE_BUILD_TYPE=Release -DWITH_IPOPT=ON -DWITH_MATLAB=ON -DWITH_PYTHON=ON -DWITH_DEEPBIND=ON ..
#For some reason, I needed to run the command above twice until `Ipopt` was detected (although `IPOPT` was being detected already)
make -j20
sudo make install
```

Now create a virtual Python environment:

```bash
sudo apt-get install python3-venv
cd ~/installations && mkdir venvs_python && cd venvs_python 
python3 -m venv ./my_venv
printf '\nalias activate_my_venv="source ~/installations/venvs_python/my_venv/bin/activate"' >> ~/.bashrc
source ~/.bashrc
activate_my_venv
```

And finally download the repo and compile it:

```bash
sudo apt-get install git-lfs ccache 
cd ~/Desktop/
mkdir ws && cd ws && mkdir src && cd src
git clone https://github.com/mit-acl/deep_panther
cd deep_panther
git lfs install
git submodule init && git submodule update
cd panther_compression/imitation
pip install numpy Cython wheel seals rospkg defusedxml empy pyquaternion pytest
pip install -e .
sudo apt-get install python3-catkin-tools #To use catkin build
sudo apt-get install ros-"${ROS_DISTRO}"-rviz-visual-tools ros-"${ROS_DISTRO}"-pybind11-catkin ros-"${ROS_DISTRO}"-tf2-sensor-msgs ros-"${ROS_DISTRO}"-jsk-rviz-plugins
cd ~/Desktop/ws/
catkin build
printf '\nsource PATH_TO_YOUR_WS/devel/setup.bash' >> ~/.bashrc #Remember to change PATH_TO_YOUR_WS
printf '\nexport PYTHONPATH="${PYTHONPATH}:$(rospack find panther)/../panther_compression"' >> ~/.bashrc 
```


To use the trained Neural Network:
```bash
roslaunch panther simulation.launch

```

Now you can click Start on the GUI, and then press G (or click the option 2D Nav Goal on the top bar of RVIZ) and click any goal for the drone. By default, `simulation.launch` will use the policy Hung_dynamic_obstacles.pt (which was trained with trefoil-knot trajectories). You can change the trajectory followed by the obstacle during testing using the `type_of_obst_traj` field of the launch file.

You can also use policies trained using a static obstacle. Simply change the field `student_policy_path` of `simulation.launch`. The available policies have the format `A_epsilon_B.pt`, where `A` is the algorithm used: Hungarian (i.e., LSA), RWTAc, or RWTAr. `B` is the epsilon used. Note that this epsilon is irrelevant for the LSA algorithm. Check the paper for further details. 


#### MATLAB (optional)

If you want to modify the optimization problem, you will need to install MATLAB and then follow these steps:


```bash
#Now, open MATLAB, and type this:
edit(fullfile(userpath,'startup.m'))
#And in that file, add this line line 
addpath(genpath('/usr/local/matlab/'))
```

Now, you can restart Matlab (or run the file `startup.m`), and make sure this works:

```bash
import casadi.*
x = MX.sym('x')
disp(jacobian(sin(x),x))
```

#### Linear Solvers

Go to [http://www.hsl.rl.ac.uk/ipopt/](http://www.hsl.rl.ac.uk/ipopt/), click on `Personal Licence, Source` to install the solver `MA27` (free for everyone), and fill and submit the form. Once you receive the corresponding email, download the compressed file, uncompress it, and place it in the folder `~/installations` (for example). Then execute the following commands:

> Note: the instructions below follow [this](https://github.com/casadi/casadi/wiki/Obtaining-HSL) closely

```bash
cd ~/installations/coinhsl-2015.06.23
wget http://glaros.dtc.umn.edu/gkhome/fetch/sw/metis/OLD/metis-4.0.3.tar.gz #This is the metis version used in the configure file of coinhsl
tar xvzf metis-4.0.3.tar.gz
#sudo make uninstall && sudo make clean #Only needed if you have installed it before
./configure LIBS="-llapack" --with-blas="-L/usr/lib -lblas" CXXFLAGS="-g -O3 -fopenmp" FCFLAGS="-g -O3 -fopenmp" CFLAGS="-g -O3 -fopenmp" #the output should say `checking for metis to compile... yes`
sudo make install #(the files will go to /usr/local/lib)
cd /usr/local/lib
sudo ln -s libcoinhsl.so libhsl.so #(This creates a symbolic link `libhsl.so` pointing to `libcoinhsl.so`). See https://github.com/casadi/casadi/issues/1437
echo "export LD_LIBRARY_PATH='\${LD_LIBRARY_PATH}:/usr/local/lib'" >> ~/.bashrc
```

<details>
  <summary> <b>Note</b></summary>

We recommend to use `MA27`. Alternatively, you can install both `MA27` and `MA57` by clicking on `Coin-HSL Full (Stable) Source` (free for academia) in [http://www.hsl.rl.ac.uk/ipopt/](http://www.hsl.rl.ac.uk/ipopt/) and then following the instructions above. Other alternative is to use the default `mumps` solver (no additional installation required), but its much slower than `MA27` or `MA57`.

</details>

Then, to use a specific linear solver, you simply need to change the name of `linear_solver_name` in the file `main.m`. You can also introduce more changes in the optimization problem in that file. After these changes, you need to run `main.m`. This will generate all the necessary files in the `casadi_generated_files` folder. These files will be read by C++.

> Note: When using a linear solver different from `mumps`, you need to start Matlab from the terminal (typing `matlab`). More info [in this issue](https://github.com/casadi/casadi/issues/2032).



================================
TODOS: 

- remove panther_extra_plus_plus??
- Change name repo (from panther to deep_panther)
- Remove the readme in https://github.com/mit-acl/panther_plus_plus/tree/master/panther/matlab
- Hacer los repos publicos!! (y change name from imitation to imitation-deep-panther?)
- Commit changes done in imitation repo!!
- Remove los roslaunch que sobran
- Explain how to use the expert directly


