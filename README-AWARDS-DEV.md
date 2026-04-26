# TrendRadar 二开使用说明

本文档说明我们这套二开版 TrendRadar 如何配合 AwardsHub 使用，重点覆盖本地源码构建、RSS 正文筛选验证和日常更新流程。

## 1. 系统关系

当前链路是：

```text
AwardsHub -> 增强 Atom/RSS -> TrendRadar -> 关键词/AI 筛选 -> 报告与推送
```

AwardsHub 负责抓取获奖信息、微信公众号文章和正文内容，并在 feed 的 `content` 中输出正文。

TrendRadar 负责订阅 AwardsHub feed，并基于 `title + summary + full_text` 做 RSS 关键词筛选；AI 筛选时也会带上摘要和正文片段。

## 2. Docker 部署方式

本项目使用 `docker-compose-awards.yml` 部署二开版 TrendRadar。

注意：该 compose 文件已经改为本地构建：

```yaml
image: trendradar-awards:dev
build:
  context: .
  dockerfile: docker/Dockerfile
```

因此本地源码修改后，需要重新 build 容器镜像才会生效。

启动或更新：

```powershell
cd C:\Workspace\20_Dev\exp-TrendRadar
docker compose -f docker-compose-awards.yml up -d --build
```

查看日志：

```powershell
docker logs -f trendradar-awards
```

停止服务：

```powershell
docker compose -f docker-compose-awards.yml down
```

## 3. 前置条件

需要先启动 AwardsHub，并确保 TrendRadar 容器能通过共享 Docker 网络访问它。

当前配置中 RSS 地址类似：

```yaml
rss:
  feeds:
    - id: "youth-cn-gn"
      name: "中国青年网-国内新闻"
      url: "http://awardshub:8642/feed/youth-cn-gn"
```

如果使用 `awardshub` 这个容器名访问，两个服务必须在同一个 Docker network 中，例如 `shared-net`。

确认网络存在：

```powershell
docker network ls
```

如不存在，可创建：

```powershell
docker network create shared-net
```

## 4. 让源码修改生效

TrendRadar 代码在 Docker 镜像构建阶段复制进 `/app/trendradar/`。

每次修改以下目录或文件后，都需要重新构建：

```text
trendradar/
docker/Dockerfile
pyproject.toml
uv.lock
```

执行：

```powershell
docker compose -f docker-compose-awards.yml up -d --build
```

验证容器内是否已经包含 RSS 正文字段：

```powershell
docker exec trendradar-awards python -c "from trendradar.storage.base import RSSItem; print('full_text' in RSSItem.__dataclass_fields__)"
```

预期输出：

```text
True
```

验证 RSS 解析器是否支持正文：

```powershell
docker exec trendradar-awards python -c "from trendradar.crawler.rss.parser import ParsedRSSItem; print('full_text' in ParsedRSSItem.__dataclass_fields__)"
```

预期输出：

```text
True
```

## 5. 配置目录

compose 中挂载了：

```yaml
volumes:
  - ./config:/app/config
  - ./output:/app/output
```

因此：

- 修改 `config/config.yaml` 不需要重建镜像，但需要重启容器或等待下一次任务读取配置。
- 修改 `config/frequency_words.txt` 不需要重建镜像。
- 修改 `trendradar/` 源码需要重建镜像。

重启容器：

```powershell
docker restart trendradar-awards
```

## 6. RSS 正文筛选验证

验证目标：确认 TrendRadar 不是只看标题，而是能用正文命中关键词。

步骤：

1. 确认 AwardsHub feed 中有正文。

```powershell
curl http://localhost:8642/feed/<source_id>
```

检查 XML 中是否存在：

```xml
<content type="text">...</content>
```

2. 在 `config/frequency_words.txt` 中临时加入一个只出现在正文、不出现在标题的词，例如：

```text
申报指南
截止时间
申报书
```

3. 清理当天 RSS 数据库，避免旧数据干扰。

```powershell
Remove-Item .\output\rss\$(Get-Date -Format yyyy-MM-dd).db -ErrorAction SilentlyContinue
```

4. 重新运行 TrendRadar。

```powershell
docker compose -f docker-compose-awards.yml up -d --build
docker logs -f trendradar-awards
```

5. 查看数据库是否已存正文。

进入容器查询：

```powershell
docker exec trendradar-awards python -c "import sqlite3; from datetime import datetime; db=datetime.now().strftime('/app/output/rss/%Y-%m-%d.db'); conn=sqlite3.connect(db); [print(row) for row in conn.execute(\"select title, length(coalesce(full_text, '')) from rss_items limit 10\")]"
```

如果 `full_text` 长度大于 0，说明正文已经入库。

6. 验证正文关键词命中。

```powershell
docker exec trendradar-awards python -c "import sqlite3; from datetime import datetime; keyword='申报指南'; db=datetime.now().strftime('/app/output/rss/%Y-%m-%d.db'); conn=sqlite3.connect(db); [print(row[0]) for row in conn.execute('select title from rss_items where title not like ? and full_text like ? limit 10', (f'%{keyword}%', f'%{keyword}%'))]"
```

如果能查到标题不含关键词、正文含关键词的文章，并且报告 RSS 区域出现该文章，就说明正文筛选生效。

## 7. 常用运维命令

重新构建并启动：

```powershell
docker compose -f docker-compose-awards.yml up -d --build
```

查看实时日志：

```powershell
docker logs -f trendradar-awards
```

进入容器：

```powershell
docker exec -it trendradar-awards bash
```

查看容器内配置：

```powershell
docker exec trendradar-awards ls -la /app/config
```

查看输出文件：

```powershell
docker exec trendradar-awards ls -la /app/output
```

## 8. 开发注意事项

- 不要直接改容器内 `/app/trendradar`，容器重建后会丢失。
- 源码修改后必须 `--build`。
- 配置和输出通过 volume 挂载，本地文件会直接影响容器。
- RSS 数据库是按日期生成的，测试时如果要排除旧数据影响，可以删除当天 `output/rss/YYYY-MM-DD.db`。
- 当前正文匹配使用 `title + summary + full_text 前 8000 字`，避免超长正文导致匹配成本过高。
