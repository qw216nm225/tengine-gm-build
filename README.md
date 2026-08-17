# tengine-gm-build

国密版 nginx（Tengine + Tongsuo）双架构编译产物流水线。

## 组合

| 组件 | 版本 | 说明 |
|---|---|---|
| [Tengine](https://github.com/alibaba/tengine) | 2.4.1 | 阿里开源的 nginx 分支，内置国密 NTLS 模块 |
| [Tongsuo 铜锁](https://github.com/Tongsuo-Project/Tongsuo) | 8.2.1 | OpenSSL 国密分支（前身 BabaSSL），编译进 Tengine |
| 国密模块 | ngx_tongsuo_ntls | Tengine 2.4.1 内置，`enable_ntls on` 启用 |

## 产物（GitHub Actions Artifacts）

| Artifact | 目标服务器 | 编译容器 | glibc |
|---|---|---|---|
| `tengine-gm-x86_64` | CentOS 7.x（x86） | centos:7.9.2009 | 2.17 |
| `tengine-gm-aarch64` | 麒麟 V10 / UOS（ARM） | almalinux:8 | 2.28 |

产物为 `/usr/local/tengine` 完整目录的 tar.gz 包。

## 触发构建

```bash
gh workflow run build.yml
gh run watch
```

## 服务器部署（不联网、无 Docker、零编译依赖）

```bash
# 1. 把对应架构的产物包拷到服务器
# 2. 解压到根目录（Tengine 安装路径为 /usr/local/tengine）
tar xzf tengine-gm-2.4.1-x86_64-centos7-glibc217.tar.gz -C /   # x86 服务器
# tar xzf tengine-gm-2.4.1-aarch64-kyv10-glibc228.tar.gz -C /   # ARM 服务器

# 3. 验证可执行
/usr/local/tengine/sbin/nginx -V

# 4. 放置证书，修改 /usr/local/tengine/conf/nginx.conf 启用双证书
# 关键配置：
#   enable_ntls on;                                    # 启用国密
#   ssl_sign_certificate / ssl_sign_certificate_key    # SM2 签名证书
#   ssl_enc_certificate  / ssl_enc_certificate_key     # SM2 加密证书
#   ssl_certificate / ssl_certificate_key              # RSA 证书（普通浏览器）

# 5. 启动
/usr/local/tengine/sbin/nginx
```

## 注意事项

- 产物依赖服务器自带的 `libpcre.so.1` 和 `libz.so.1`（CentOS 7 / 麒麟 V10 均自带，无需额外安装）
- 证书私钥**不要**提交到本仓库
- 首次在麒麟 V10 上部署时建议先 `nginx -t` 检查配置再启动
