#!/bin/bash

# 脚本：MariaDB数据库备份和还原
# 功能：提供MariaDB数据库的备份和还原功能
# 特性：
#   - 支持全库备份和指定数据库备份
#   - 支持从备份文件恢复数据
#   - 备份文件自动压缩和日期命名
#   - 错误处理和日志记录

# 配置参数
BACKUP_DIR="/var/backups/mariadb"  # 备份文件存储目录
LOG_FILE="/var/log/mariadb_backup.log"  # 日志文件
DATE_FORMAT="%Y%m%d_%H%M%S"  # 日期格式
DB_USER="root"  # 数据库用户名
DB_PASSWORD=""  # 数据库密码，如果为空则使用无密码登录

# 创建日志函数
log_message() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# 确保脚本以root权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要root权限运行，请使用sudo或以root身份运行"
    exit 1
}

# 确保备份目录存在
ensure_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_message "创建备份目录: $BACKUP_DIR"
    fi
}

# 确保日志目录存在
ensure_log_dir() {
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
        log_message "创建日志目录: $log_dir"
    fi
}

# 备份单个数据库
backup_database() {
    local db_name="$1"
    local backup_file="$BACKUP_DIR/${db_name}_$(date +$DATE_FORMAT).sql"
    
    log_message "开始备份数据库: $db_name"
    
    # 构建mysqldump命令
    local mysqldump_cmd="mysqldump"
    if [ -n "$DB_USER" ]; then
        mysqldump_cmd="$mysqldump_cmd -u $DB_USER"
    fi
    
    if [ -n "$DB_PASSWORD" ]; then
        mysqldump_cmd="$mysqldump_cmd -p$DB_PASSWORD"
    fi
    
    # 执行备份
    if $mysqldump_cmd --single-transaction --quick --lock-tables=false "$db_name" > "$backup_file"; then
        # 压缩备份文件
        gzip -f "$backup_file"
        log_message "数据库 $db_name 备份成功: ${backup_file}.gz"
        echo "备份文件: ${backup_file}.gz"
    else
        log_message "错误: 数据库 $db_name 备份失败"
        echo "错误: 数据库 $db_name 备份失败"
        return 1
    fi
    
    return 0
}

# 备份所有数据库
backup_all_databases() {
    local backup_file="$BACKUP_DIR/all_databases_$(date +$DATE_FORMAT).sql"
    
    log_message "开始备份所有数据库"
    
    # 构建mysqldump命令
    local mysqldump_cmd="mysqldump"
    if [ -n "$DB_USER" ]; then
        mysqldump_cmd="$mysqldump_cmd -u $DB_USER"
    fi
    
    if [ -n "$DB_PASSWORD" ]; then
        mysqldump_cmd="$mysqldump_cmd -p$DB_PASSWORD"
    fi
    
    # 执行备份
    if $mysqldump_cmd --all-databases --single-transaction --quick --lock-tables=false > "$backup_file"; then
        # 压缩备份文件
        gzip -f "$backup_file"
        log_message "所有数据库备份成功: ${backup_file}.gz"
        echo "备份文件: ${backup_file}.gz"
    else
        log_message "错误: 所有数据库备份失败"
        echo "错误: 所有数据库备份失败"
        return 1
    fi
    
    return 0
}

# 还原数据库
restore_database() {
    local backup_file="$1"
    local db_name="$2"
    
    # 检查备份文件是否存在
    if [ ! -f "$backup_file" ]; then
        log_message "错误: 备份文件不存在: $backup_file"
        echo "错误: 备份文件不存在: $backup_file"
        return 1
    fi
    
    log_message "开始还原数据库: $db_name (从文件: $backup_file)"
    
    # 检查文件是否为gzip压缩文件
    local is_gzipped=0
    if [[ "$backup_file" == *.gz ]]; then
        is_gzipped=1
    fi
    
    # 构建mysql命令
    local mysql_cmd="mysql"
    if [ -n "$DB_USER" ]; then
        mysql_cmd="$mysql_cmd -u $DB_USER"
    fi
    
    if [ -n "$DB_PASSWORD" ]; then
        mysql_cmd="$mysql_cmd -p$DB_PASSWORD"
    fi
    
    # 如果指定了数据库名，先创建数据库（如果不存在）
    if [ -n "$db_name" ]; then
        echo "CREATE DATABASE IF NOT EXISTS \`$db_name\`;" | $mysql_cmd
        mysql_cmd="$mysql_cmd $db_name"
    fi
    
    # 执行还原
    if [ $is_gzipped -eq 1 ]; then
        if gunzip < "$backup_file" | $mysql_cmd; then
            log_message "数据库还原成功"
            echo "数据库还原成功"
        else
            log_message "错误: 数据库还原失败"
            echo "错误: 数据库还原失败"
            return 1
        fi
    else
        if $mysql_cmd < "$backup_file"; then
            log_message "数据库还原成功"
            echo "数据库还原成功"
        else
            log_message "错误: 数据库还原失败"
            echo "错误: 数据库还原失败"
            return 1
        fi
    fi
    
    return 0
}

# 列出可用的备份文件
list_backups() {
    echo "可用的备份文件:"
    if [ -d "$BACKUP_DIR" ]; then
        ls -lh "$BACKUP_DIR" | grep -E "\.sql(\.gz)?$"
    else
        echo "备份目录不存在: $BACKUP_DIR"
    fi
}

# 清理旧备份文件
cleanup_old_backups() {
    local days="$1"
    
    if [ -z "$days" ]; then
        days=30  # 默认保留30天的备份
    fi
    
    log_message "清理 $days 天前的备份文件"
    
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$days -delete -print | while read file; do
            log_message "已删除旧备份文件: $file"
        done
    fi
}

# 显示帮助信息
show_help() {
    echo "MariaDB数据库备份和还原脚本"
    echo "用法:"
    echo "  $0 backup [数据库名]     # 备份指定数据库，不指定则备份所有数据库"
    echo "  $0 restore 备份文件 [数据库名]  # 还原备份文件到指定数据库"
    echo "  $0 list                  # 列出可用的备份文件"
    echo "  $0 cleanup [天数]        # 清理指定天数之前的备份文件，默认30天"
    echo "  $0 help                  # 显示此帮助信息"
}

# 主函数
main() {
    ensure_log_dir
    ensure_backup_dir
    
    local command="$1"
    shift
    
    case "$command" in
        backup)
            local db_name="$1"
            if [ -z "$db_name" ]; then
                backup_all_databases
            else
                backup_database "$db_name"
            fi
            ;;
        restore)
            local backup_file="$1"
            local db_name="$2"
            if [ -z "$backup_file" ]; then
                echo "错误: 未指定备份文件"
                show_help
                exit 1
            fi
            restore_database "$backup_file" "$db_name"
            ;;
        list)
            list_backups
            ;;
        cleanup)
            local days="$1"
            cleanup_old_backups "$days"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "错误: 未知命令 '$command'"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

main "$@"
