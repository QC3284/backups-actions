# GitHub Repository Backup and Release

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

这是一个使用GitHub Actions自动备份GitHub仓库的项目。它会将指定的仓库列表克隆并压缩后，以GitHub Release的形式存储。

## 功能特性

- 🕒 **定时自动备份**：每天UTC时间凌晨4点自动运行
- 🚀 **手动触发备份**：随时通过Workflow Dispatch触发
- 📦 **高效压缩**：使用Zstandard(ZSTD)算法进行高压缩比备份
- 🔒 **安全存储**：备份存储在GitHub Releases中
- 📊 **详细报告**：生成备份成功/失败报告
- ✂️ **大仓库支持**：自动分卷处理超过1.8GB的仓库
- 💾 **空间优化**：智能磁盘空间管理

## 使用指南

### 准备工作

1. **Fork 此仓库**
2. **配置仓库 Secrets**
   - 默认使用`secrets.GITHUB_TOKEN`，无需额外配置（有写入仓库的权限）
3. **编辑备份列表**
   - 在仓库根目录创建文件 `back_ck_url.txt`
   - 每行一个仓库URL（支持HTTPS或SSH格式），例如：
     ```
     https://github.com/username/repo1.git
     git@github.com:username/repo2.git
     # 注释行以#开头
     ```

### 运行备份

- **手动运行**：在仓库的Actions标签页中，选择"Repository Backup and Release"工作流，点击"Run workflow"
- **定时运行**：工作流会在每天UTC时间4点自动运行

### 查看备份结果

1. **访问Releases页面**：
   - 前往仓库的 **Releases** 页面（通常在仓库首页的右侧菜单）
   - 查找以 `backup-` 开头并带有时间戳的标签（例如：`backup-20250101000000`）

2. **阅读备份报告**：
   - 每个发布版本的说明中包含一份 **备份摘要报告**
   - 报告分为两部分：
     - **✅ 成功备份**：列出所有成功备份的仓库
     - **❌ 备份失败**：列出备份过程中失败的仓库及原因（如果有）

3. **下载备份文件**：
   - 在发布版本的 **Assets** 部分，可以下载所有备份的压缩文件
   - 备份文件命名格式：`{仓库所有者}-{仓库名}-{时间戳}.tar.zst`
   - **注意**：对于大型仓库，备份文件会被分割为多个分卷文件（每个不超过1.8GB），命名格式为：`{原文件名}.part000`、`{原文件名}.part001` 等

4. **处理分卷文件**：
   - 如果仓库备份被分割成多个分卷文件，你需要下载 **所有** 属于同一个仓库的分卷文件
   - 使用命令行合并分卷文件：
     ```bash
     cat {文件名}.part* > {完整文件名}.tar.zst
     ```
     例如：
     ```bash
     cat octocat-hello-world-1672531200.tar.zst.part* > octocat-hello-world-1672531200.tar.zst
     ```

### 恢复备份

1. 下载备份文件（如果分卷，需要下载所有分卷）
2. 合并分卷文件（如果需要）：
   ```bash
   cat filename.tar.zst.part* > filename.tar.zst
   ```
3. 解压备份文件：
   ```bash
   zstd -d filename.tar.zst
   tar xvf filename.tar
   ```
4. 恢复Git仓库：
   ```bash
   cd repo.git
   git init --bare
   ```

## 技术细节

### 备份流程

1. 创建新的Release草稿
2. 逐个克隆仓库
3. 使用ZSTD压缩仓库内容
4. 大文件自动分卷处理（>1.8GB）
5. 上传备份文件到Release
6. 生成备份报告并发布Release

### 分卷处理

当备份文件超过1.8GB时，系统会自动分割文件为多个分卷：
- 分卷大小：1.8GB（1800MB）
- 命名格式：`原文件名.part000`, `原文件名.part001`等
- 合并命令：`cat filename.part* > fullfile.zst`

## 许可协议

本项目采用 **GNU General Public License v3.0** 授权。
完整的许可协议请查看 [LICENSE](LICENSE) 文件。

## 贡献指南

欢迎通过Issue或Pull Request贡献代码！请确保：
- 遵循现有代码风格
- 包含必要的测试
- 更新相关文档

---

**温馨提示**：
- 备份完成后，您会收到GitHub的通知邮件（可在账户设置中配置）
- 定期检查备份文件完整性，建议每季度进行一次恢复测试
- 大型仓库（>1GB）可能需要较长时间处理，请耐心等待
