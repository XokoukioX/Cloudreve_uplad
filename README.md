
# Cloudreve File Upload Script

## 功能介绍
该脚本用于将指定文件上传到 Cloudreve 存储服务。它支持分块上传，并在上传过程中显示进度条。

## 技术细节

- **使用工具**：`curl` 和 `jq`。
- **上传流程**：
  1. 登录 Cloudreve 并获取会话 Cookie。
  2. 获取上传文件的基本信息（大小、名称、最后修改时间）。
  3. 查询目标路径的 policy ID。
  4. 初始化上传，处理会话冲突。
  5. 分块上传文件，并更新进度条。
  6. 清理临时文件和目录。

- \~**进度条实现**：使用 ANSI 转义序列控制光标位置，确保进度条在屏幕底部实时更新。\~

## 注意事项

- 确保安装了 `curl` 和 `jq`。
- 该脚本需要在支持 ANSI 转义序列的终端中运行。
- 确保 API 权限设置允许执行上传和删除操作。
- 使用前，请根据实际情况替换用户名、密码和服务器地址等信息。

## 使用教程

1. **准备工作**：
   确保安装了必要的工具：
   ```bash
   sudo apt-get install curl jq
   ```

2. **使用脚本**：
   将脚本保存为 `upload.sh`，并赋予执行权限：
   ```bash
   chmod +x upload.sh
   ```

3. **运行脚本**：
   使用以下命令运行脚本：
   ```bash
   ./upload.sh <file_path> <upload_path> [--debug]
   ```
   - `<file_path>`：要上传的文件的路径。
   - `<upload_path>`：在 Cloudreve 中的目标上传路径。
   - `--debug`（可选）：启用调试模式，输出详细的调试信息。

## 示例
```bash
./upload.sh /path/to/your/file.txt /path/in/cloudreve --debug
```

## 许可证
MIT License

##特别感谢
ChatGPT
```
