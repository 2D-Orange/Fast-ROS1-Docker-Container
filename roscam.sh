#!/bin/bash

CONTAINER_NAME="roscam"
IMAGE_NAME="ros_noetic_cam_image"

# 1. 检查容器是否已经运行（处理多开命令行的需求）
if [ "$(docker ps -q -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "<!>检测到容器 ${CONTAINER_NAME} 正在运行，开启新终端进入..."
    docker exec -it ${CONTAINER_NAME} bash
    exit 0
fi

# 2. 开放主机的 X11 访问权限，允许容器调用宿主机的图形界面（RViz 需要）
xhost +local:root > /dev/null 2>&1

# 3. 检查基础镜像是否已构建，如果没有则按要求自动构建
if ! docker images --format "{{.Repository}}" | grep -q "^${IMAGE_NAME}$"; then
    echo "<!>未找到自定义镜像 ${IMAGE_NAME}，开始构建..."
    
    # 使用 Here Document 动态传入 Dockerfile 进行构建
    cat <<EOF | docker build -t ${IMAGE_NAME} -
FROM osrf/ros:noetic-desktop-full

# 替换 Ubuntu 软件源为清华源 (ROS Noetic 基于 Ubuntu 20.04 Focal)
RUN sed -i 's/archive.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \\
    sed -i 's/security.ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list

# 替换 ROS 软件源为清华源
RUN echo "deb https://mirrors.tuna.tsinghua.edu.cn/ros/ubuntu/ focal main" > /etc/apt/sources.list.d/ros-latest.list && \\
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys F42ED6FBAB17C654

# 安装所需软件
RUN apt-get update && apt-get install -y \
    vim \
    nano \
    iputils-ping \
    ros-noetic-usb-cam \
    python3-pip \
    libcanberra-gtk-module \
    libcanberra-gtk3-module \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python 库 (添加 --no-cache-dir 可以减小镜像体积)
RUN pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple && \\
    pip3 install --no-cache-dir ultralytics

# 写入环境变量配置
RUN echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc

# 注意：Docker 构建时每执行一个 RUN 都是一个独立的层，
# 所以单独写 RUN source ~/.bashrc 是无效的。
# 只要写入了 ~/.bashrc，当你通过 bash 进入容器时它就会自动生效。
EOF
fi

# 4. 首次启动：创建并运行“用完即焚”的容器
echo "<!>启动并进入容器 ${CONTAINER_NAME} ..."
docker run -it --rm \
    --ipc=host \
    --name ${CONTAINER_NAME} \
    --gpus all \
    --device /dev/dri \
    --env="DISPLAY=$DISPLAY" \
    --env="QT_X11_NO_MITSHM=1" \
    --env="NVIDIA_DRIVER_CAPABILITIES=all" \
    --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    --volume="$HOME/workspace/ros1:/root/workspace" \
    --device="/dev/video4:/dev/video0" \
    ${IMAGE_NAME} bash

