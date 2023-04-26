# 基础镜像
FROM ubuntu:latest
# 修改国内源
RUN sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
RUN sed -i 's/security.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
# 执行命令
# 安装 python3、openai、streamlit、golang
RUN apt-get update \
  && apt-get install gcc libc6-dev git lrzsz -y \
  && apt-get install python3 python3-dev python3-pip -y \
  && pip install openai streamlit poe-api \
  && apt-get install golang -y \
  && apt-get clean \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*
# 建立软链接
RUN ln -s /usr/bin/python3 /usr/bin/python
# 配置环境变量
ENV GOROOT=/usr/lib/go        
ENV PATH=$PATH:/usr/lib/go/bin 
ENV GOPATH=/root/go
ENV PATH=$GOPATH/bin/:$PATH
# 定制工作目录
RUN mkdir -p /root/go/src/github.com/keontang/
WORKDIR /root/go/src/github.com/keontang/

EXPOSE 80
EXPOSE 8080
EXPOSE 8501

ENTRYPOINT ["/bin/bash"]
