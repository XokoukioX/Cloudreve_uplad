#!/bin/bash

# 检查输入参数
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <file_path> <upload_path>"
    exit 1
fi

# 文件路径和上传路径
file_path="$1"
upload_path="$2"

# 认证信息和服务器地址
username=""  # 替换为你的用户名
password=""  # 替换为你的密码
server_url=""  # 替换为你的服务器地址

# 调试标志，默认开启调试
DEBUG=false

# 打印调试信息的函数
debug_echo() {
    if [ "$DEBUG" = true ]; then
        echo "$1"
    fi
}

# 登录并获取 cloudreve-session Cookie
login() {
    debug_echo "Logging in to the server..."
    login_response=$(curl -i -s --location --request POST "$server_url/api/v3/user/session" \
    --header 'Content-Type: application/json' \
    -d '{
        "userName": "'"$username"'",
        "Password": "'"$password"'",
        "captchaCode": ""
    }')

    # 提取 cloudreve-session Cookie
    cloudreve_session=$(echo "$login_response" | grep -oP 'cloudreve-session=\K[^;]+')
    if [ -z "$cloudreve_session" ]; then
        echo "Login Failed! Could not retrieve cloudreve-session Cookie. Response: $login_response"
        exit 1
    fi
    debug_echo "Retrieved cloudreve-session: $cloudreve_session"
}

# 初次登录
login

# 获取上传文件的基本信息
debug_echo "Getting file information..."
size=$(stat -c%s "$file_path")
name=$(basename "$file_path")
last_modified=$(stat -c%Y "$file_path")
debug_echo "File size: $size, File name: $name, Last modified: $last_modified"

# 确保上传路径被正确编码
encoded_path=$(echo -n "$upload_path" | jq -sRr @uri)
debug_echo "Encoded Path: $encoded_path"

# 查询目录信息获取 policy_id
debug_echo "Fetching policy ID from the server..."
policy_response=$(curl -s --location --request GET "$server_url/api/v3/directory$encoded_path" \
--header "Cookie: cloudreve-session=$cloudreve_session" \
--header 'Content-Type: application/json')

debug_echo "Policy Response: $policy_response"  # 调试输出响应内容
policy_id=$(echo "$policy_response" | jq -r .data.policy.id)

# 检查是否成功获取 policy_id
if [ -z "$policy_id" ] || [ "$policy_id" == "null" ]; then
    echo "Failed to get policy_id! Check directory path and API response: $policy_response"
    exit 1
fi
debug_echo "Retrieved Policy ID: $policy_id"

# 尝试获取上传文件的 session ID
debug_echo "Initializing file upload..."
upload_init_response=$(curl -s --location --request PUT "$server_url/api/v3/file/upload" \
--header "Cookie: cloudreve-session=$cloudreve_session" \
--header 'Content-Type: application/json' \
-d "{
    \"path\": \"$upload_path\",
    \"size\": $size,
    \"name\": \"$name\",
    \"policy_id\": \"$policy_id\",
    \"last_modified\": $last_modified,
    \"mime_type\": \"\"
}")

debug_echo "Upload Init Response: $upload_init_response"  # 调试上传初始化
si=$(echo "$upload_init_response" | jq -r .data.sessionID)

# 检查 session ID 是否获取成功
if [ -z "$si" ] || [ "$si" == "null" ]; then
    code=$(echo "$upload_init_response" | jq -r .code)
    if [ "$code" == "40054" ]; then
        echo "An existing upload session was detected. Attempting to clean up existing session..."

        # 执行删除请求以清理现有会话
        cleanup_response=$(curl -s --location --request DELETE "$server_url/api/v3/file/upload" \
        --header "Cookie: cloudreve-session=$cloudreve_session" \
        --header 'Content-Type: application/json')

        debug_echo "Cleanup Response: $cleanup_response"
        if [ $(echo "$cleanup_response" | jq -r .code) -ne 0 ]; then
            echo "Failed to clean up existing session! Response: $cleanup_response"
            # 在这里可以选择重新登录以重置会话
            login
        fi
        debug_echo "Existing upload session cleaned up. Retrying upload initialization..."

        # 重新初始化上传
        upload_init_response=$(curl -s --location --request PUT "$server_url/api/v3/file/upload" \
        --header "Cookie: cloudreve-session=$cloudreve_session" \
        --header 'Content-Type: application/json' \
        -d "{
            \"path\": \"$upload_path\",
            \"size\": $size,
            \"name\": \"$name\",
            \"policy_id\": \"$policy_id\",
            \"last_modified\": $last_modified,
            \"mime_type\": \"\"
        }")
        si=$(echo "$upload_init_response" | jq -r .data.sessionID)

        if [ -z "$si" ] || [ "$si" == "null" ]; then
            echo "Failed to get session ID after cleanup! Response: $upload_init_response"
            exit 1
        fi
    fi
fi

debug_echo "Retrieved Session ID: $si"

# 创建临时目录存放分块文件
temp_dir=$(mktemp -d)
debug_echo "Creating temporary directory: $temp_dir"

# 分片信息
chunk_size=26214400  # 25MB
debug_echo "Splitting file into chunks..."
split -b $chunk_size "$file_path" "$temp_dir/chunk_"

# 计算总分片数
total_chunks=$(ls "$temp_dir" | wc -l)

# 在屏幕特定位置输出准备信息
echo -e "\n准备上传文件: $name"
echo "文件大小: $size 字节"
echo "总分块数: $total_chunks"
echo -e "\n上传进度:"

# 上传进度条函数
show_progress() {
    local current=$1
    local total=$2
    local percent=$(( current * 100 / total ))
    local filled_length=$(( percent * 50 / 100 ))
    local bar=$(printf "%-${filled_length}s" '#' | tr ' ' '#')
    local empty_bar=$(printf "%-$((50 - filled_length))s" '' | tr ' ' '.')
    # 保持在最后一行打印进度条
    printf "\033[${LINES};0H[${bar}${empty_bar}][${percent}%%] (已上传分块: $current/$total)"
}

upload_chunk() {
    debug_echo "Uploading chunk: $2"
    response=$(curl -s --location --request POST "$server_url/api/v3/file/upload/${si}/$2" \
        --header "Cookie: cloudreve-session=$cloudreve_session" \
        --header 'Content-Type: application/octet-stream' \
        --data-binary "@$1")

    debug_echo "Upload Chunk Response: $response"
    if [ $(echo "$response" | jq -r .code) -ne 0 ]; then
        echo "Chunk $2 upload failed! Response: $response"
        exit 1
    fi
    
    # 更新进度条
    show_progress $(( ++upload_index )) $total_chunks
}

# 上传所有分块
upload_index=0
for chunk in "$temp_dir"/chunk_*; do
    upload_chunk "$chunk" "$upload_index"
done

# 清理临时文件夹
rm -rf "$temp_dir"

# 上传完成后输出总结
echo -e "\n上传完成！"
echo "文件名: $name"
echo "文件大小: $size 字节"
echo "总分块数: $total_chunks"
echo "成功上传分块数: $upload_index"
