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
  && apt-get install wget vim curl unzip -y \
  && apt-get clean \
  && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*
# 建立软链接
RUN ln -s /usr/bin/python3 /usr/bin/python
# install golang
RUN wget https://go.dev/dl/go1.20.1.linux-amd64.tar.gz \
  && tar -C /usr/local -xzf go1.20.1.linux-amd64.tar.gz \
  && rm go1.20.1.linux-amd64.tar.gz
# 配置环境变量
ENV GOROOT=/usr/local/go
ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/root/go
ENV PATH=$PATH:$GOPATH/bin/
# 定制工作目录
RUN mkdir -p /root/go/src \
  && mkdir -p /root/go/bin \
  && mkdir -p /root/go/keontang
WORKDIR /root/go/keontang/

# 安装 hertz
RUN go install github.com/cloudwego/hertz/cmd/hz@latest
# 安装 kitex
RUN go install github.com/cloudwego/kitex/tool/cmd/kitex@latest \
  && go install github.com/cloudwego/thriftgo@latest
# 安装 protocol 编译器
RUN PROTOC_VERSION=$(curl -s \
  "https://api.github.com/repos/protocolbuffers/protobuf/releases/latest" \
  | grep -Po '"tag_name": "v\K[0-9.]+') \
  && curl -Lo protoc.zip \
  "https://github.com/protocolbuffers/protobuf/releases/latest/download/protoc-${PROTOC_VERSION}-linux-x86_64.zip" \
  && unzip protoc.zip -d /usr/local \
  && chmod a+x /usr/local/bin/protoc \
  && rm -rf protoc.zip
# 安装 protocol golang 插件：protoc-gen-go
RUN go install github.com/golang/protobuf/protoc-gen-go@latest
# 安装 golangci-lint; refer to: https://golangci-lint.run/usage/install/
RUN curl -sSfL \
  https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
  | sh -s -- -b /root/go/bin v1.53.3

EXPOSE 80
EXPOSE 8080

ENTRYPOINT ["/bin/bash"]
