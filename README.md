# tengine-gm-build

国密版 nginx（Tengine + Tongsuo）双架构编译产物与上线部署教程。

## 组合

| 组件 | 版本 | 说明 |
|---|---|---|
| [Tengine](https://github.com/alibaba/tengine) | 2.4.1 | 阿里开源的 nginx 分支，内置国密 NTLS 模块 |
| [Tongsuo 铜锁](https://github.com/Tongsuo-Project/Tongsuo) | 8.2.1 | OpenSSL 国密分支（前身 BabaSSL），**静态编译进** Tengine |
| 国密模块 | ngx_tongsuo_ntls | Tengine 2.4.1 内置，`enable_ntls on` 启用 |

## 产物（GitHub Actions Artifacts）

| Artifact | 目标服务器 | 编译容器 | glibc 要求 |
|---|---|---|---|
| `tengine-gm-x86_64` | CentOS 7.x（x86_64） | centos:7.9.2009 | >= 2.17（CentOS 7 自带） |
| `tengine-gm-aarch64` | 麒麟 V10 / UOS（aarch64） | almalinux:8 | >= 2.28（麒麟 V10 自带） |

- 产物为 `/usr/local/tengine` 目录的 tar.gz（包内路径 `tengine/`，解压到 `/usr/local`）
- **功能已由流水线自测验证**：产物在编译容器内启动 + GmSSL 标准 TLCP 客户端国密握手 PASS
- 动态依赖仅 6 个基础库（libc/libcrypt/libdl/libpcre.so.1/libpthread/libz），目标系统均自带

## 触发构建

```bash
gh workflow run build.yml
gh run watch
```

流水线包含：x86_64 编译（含容器内国密握手自测）+ aarch64 编译。

---

# 上线部署教程

## 步骤 1：上传产物并解压

把与服务器架构匹配的产物包传到服务器（x86 服务器用 `x86_64` 包，ARM/麒麟用 `aarch64` 包）：

```bash
tar xzf tengine-gm-2.4.1-x86_64-centos7-glibc217.tar.gz -C /usr/local
# ARM 服务器：tar xzf tengine-gm-2.4.1-aarch64-kyv10-glibc228.tar.gz -C /usr/local
/usr/local/tengine/sbin/nginx -V   # 应显示 Tengine/2.4.1
```

## 步骤 2：部署前体检

下载 `deploy/precheck.sh` 到服务器，执行：

```bash
bash precheck.sh 443     # 参数为计划监听端口
```

体检项：架构匹配、内核版本、glibc 版本、动态库依赖（ldd）、端口占用、SELinux、防火墙、磁盘空间。**出现 FAIL 先处理再继续；WARN 项不影响启动。**

## 步骤 3：放置证书

```bash
mkdir -p /usr/local/tengine/conf/certs
# 上传 4 个国密证书文件（CFCA/阿里云等国密证书包的交付形态）：
#   SM2 签名证书 + 私钥 -> sign.pem / sign.key（pem 需含证书链，即"网站证书+中间CA+根"拼接）
#   SM2 加密证书 + 私钥 -> enc.pem  / enc.key
# 若需普通浏览器访问（双证书方案），另备 RSA 证书 server.pem / server.key
chmod 600 /usr/local/tengine/conf/certs/*.key
```

## 步骤 4：配置 nginx.conf

以 `deploy/nginx-gm.conf.example` 为模板（已含双证书完整写法与反向代理示例）：

```bash
cp nginx-gm.conf.example /usr/local/tengine/conf/nginx.conf
# 修改 server_name、证书文件名、location 转发目标
vi /usr/local/tengine/conf/nginx.conf
```

关键指令（Tengine 国密特有）：

```nginx
enable_ntls on;                       # 国密开关
ssl_sign_certificate      certs/sign.pem;   # SM2 签名证书
ssl_sign_certificate_key  certs/sign.key;
ssl_enc_certificate       certs/enc.pem;    # SM2 加密证书
ssl_enc_certificate_key   certs/enc.key;
```

## 步骤 5：配置检查并启动

```bash
/usr/local/tengine/sbin/nginx -t -p /usr/local/tengine   # 必须通过才能启动
```

**注意：所有命令必须带 `-p /usr/local/tengine`**（产物编译时 prefix 为编译容器内路径，需 -p 覆盖）。

直接启动：

```bash
/usr/local/tengine/sbin/nginx -p /usr/local/tengine
```

systemd 方式（推荐，开机自启 + 失败拉起）：

```bash
cp deploy/tengine.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now tengine
systemctl status tengine
```

## 步骤 6：验证

**国密通道**（命令行，无需浏览器）：

```bash
# 用 GmSSL 的 tlcp_client（标准 TLCP 客户端），输出 Connection established! 即成功
gmssl tlcp_client -host 127.0.0.1 -port 443
```

或使用国密浏览器（奇安信/密信/360 国密）访问，观察"国密通道/SM2"标识。

**RSA 通道**（配置了 RSA 证书时）：

```bash
curl -vI https://yourdomain.com/     # 普通 curl/浏览器能通即 RSA 通道正常
```

## 步骤 7：回滚方案

```bash
systemctl stop tengine                          # 停止新 Tengine
systemctl start nginx                           # 恢复旧 nginx（若存在）
# 新 Tengine 装在 /usr/local/tengine，与旧 nginx 完全隔离，互不影响
```

---

# 附：自签测试证书生成参考

测试环境需自签 SM2 证书时，**必须携带 Key Usage 扩展**（国密 nginx 以此为"国密证书类型"判定依据，缺失会报 `unknown gm certificate type`）：

```bash
# 签名证书（digitalSignature）
openssl ecparam -genkey -name SM2 -out sign.key
openssl req -new -x509 -days 365 -key sign.key -out sign.pem -subj "/CN=localhost" \
  -addext "keyUsage=critical,digitalSignature,nonRepudiation"
# 加密证书（keyEncipherment）
openssl ecparam -genkey -name SM2 -out enc.key
openssl req -new -x509 -days 365 -key enc.key -out enc.pem -subj "/CN=localhost" \
  -addext "keyUsage=critical,keyEncipherment,keyAgreement"
```

## 注意事项

- 证书私钥**不要**提交到本仓库
- 本仓库 `test-certs/` 仅为 localhost 自签测试证书，无任何敏感信息
- 生产证书建议找支持国密的 CA 申请（CFCA、阿里云证书服务等），交付形态即上文 4 个文件
- 产物依赖服务器自带 `libpcre.so.1`/`libcrypt.so.1`/`libz.so.1`（目标系统均自带；极简裁剪系统以 precheck 为准）
