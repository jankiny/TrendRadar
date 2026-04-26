# TrendRadar 二开使用说明

本文档说明我们这套二开版 TrendRadar 如何配合 AwardsHub 使用，重点覆盖本地源码构建、RSS 正文筛选验证和日常更新流程。

## 1. 系统关系

当前链路：

```text
AwardsHub -> 增强 Atom/RSS -> TrendRadar -> 关键词/AI 筛选 -> 报告与推送
```

AwardsHub 负责抓取获奖信息、微信公众号文章和正文内容，并在 feed 的 `content` 中输出正文。

TrendRadar 负责订阅 AwardsHub feed，并基于 `title + summary + full_text` 做 RSS 关键词筛选；AI 筛选时也会带上摘要和正文片段。

## 2. Docker 部署方式

Awards 版本的 compose 文件位于：

```text
docker/docker-compose-awards.yml
```

该 compose 文件使用本地源码构建镜像：

```yaml
image: trendradar-awards:dev
build:
  context: ..
  dockerfile: docker/Dockerfile
```

因为 compose 文件在 `docker/` 目录下，所以路径都已经按 `docker/` 为基准核对：

```yaml
volumes:
  - ../config:/app/config
  - ../output:/app/output
  - ../scripts/entrypoint-awards.sh:/entrypoint-awards.sh:ro
  - ../scripts/generate_keywords.sh:/generate_keywords.sh:ro
```

启动或更新：

```powershell
cd C:\Workspace\20_Dev\exp-TrendRadar
docker compose -f docker/docker-compose-awards.yml up -d --build
```

如果 8080 端口被占用，可以临时换端口：

```powershell
$env:WEBSERVER_PORT="18080"
docker compose -f docker/docker-compose-awards.yml up -d --build
```

访问地址：

```text
http://127.0.0.1:18080
```

查看日志：

```powershell
docker logs -f trendradar-awards
```

停止服务：

```powershell
docker compose -f docker/docker-compose-awards.yml down
```

## 3. 前置条件

需要先启动 AwardsHub，并确保 TrendRadar 容器能通过共享 Docker 网络访问它。

当前 TrendRadar 配置中的 RSS 地址类似：

```yaml
rss:
  feeds:
    - id: "youth-cn-gn"
      name: "中国青年网-国内新闻"
      url: "http://awardshub:8642/feed/youth-cn-gn"
```

如果使用 `awardshub` 这个容器名访问，AwardsHub 和 TrendRadar 必须在同一个 Docker network 中，例如 `shared-net`。

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

每次修改以下内容后，都需要重新构建镜像：

```text
trendradar/
docker/Dockerfile
pyproject.toml
uv.lock
```

执行：

```powershell
docker compose -f docker/docker-compose-awards.yml up -d --build
```

配置和输出目录通过 volume 挂载，本地改动会直接进入容器：

```text
config/
output/
scripts/entrypoint-awards.sh
scripts/generate_keywords.sh
```

修改 `config/config.yaml` 或 `config/frequency_words.txt` 后，通常只需要重启容器或等待下一次任务读取配置：

```powershell
docker restart trendradar-awards
```

## 5. 验证二开代码已进入容器

验证 `RSSItem` 已包含 `full_text`：

```powershell
docker exec trendradar-awards python -c "from trendradar.storage.base import RSSItem; print('full_text' in RSSItem.__dataclass_fields__)"
```

预期输出：

```text
True
```

验证 RSS 解析器已包含 `full_text`：

```powershell
docker exec trendradar-awards python -c "from trendradar.crawler.rss.parser import ParsedRSSItem; print('full_text' in ParsedRSSItem.__dataclass_fields__)"
```

预期输出：

```text
True
```

## 6. 验证 RSS 正文筛选

验证目标：确认 TrendRadar 不是只看标题，而是能用正文命中关键词。

1. 确认 AwardsHub feed 中有正文：

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

3. 清理当天 RSS 数据库，避免旧数据干扰：

```powershell
Remove-Item .\output\rss\$(Get-Date -Format yyyy-MM-dd).db -ErrorAction SilentlyContinue
```

4. 重新运行 TrendRadar：

```powershell
docker compose -f docker/docker-compose-awards.yml up -d --build
docker logs -f trendradar-awards
```

5. 查看数据库是否已存正文：

```powershell
docker exec trendradar-awards python -c "import sqlite3; from datetime import datetime; db=datetime.now().strftime('/app/output/rss/%Y-%m-%d.db'); conn=sqlite3.connect(db); [print(row) for row in conn.execute(\"select title, length(coalesce(full_text, '')) from rss_items limit 10\")]"
```

如果 `full_text` 长度大于 0，说明正文已经入库。

6. 验证正文关键词命中：

```powershell
docker exec trendradar-awards python -c "import sqlite3; from datetime import datetime; keyword='申报指南'; db=datetime.now().strftime('/app/output/rss/%Y-%m-%d.db'); conn=sqlite3.connect(db); [print(row[0]) for row in conn.execute('select title from rss_items where title not like ? and full_text like ? limit 10', (f'%{keyword}%', f'%{keyword}%'))]"
```

如果能查到标题不含关键词、正文含关键词的文章，并且报告 RSS 区域出现该文章，就说明正文筛选生效。

## 7. 常用命令

重新构建并启动：

```powershell
docker compose -f docker/docker-compose-awards.yml up -d --build
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

- 不要直接修改容器内 `/app/trendradar`，容器重建后会丢失。
- 源码修改后必须使用 `--build`。
- `config/` 和 `output/` 通过 volume 挂载，本地文件会直接影响容器。
- RSS 数据库按日期生成，测试时如需排除旧数据影响，可删除当天 `output/rss/YYYY-MM-DD.db`。
- 当前正文匹配使用 `title + summary + full_text 前 8000 字`，避免超长正文导致匹配成本过高。
