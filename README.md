# VOD Web

MacCMS 采集 API 聚合点播网站，基于 Next.js 全栈构建。

## 功能

- 首页展示最新影片
- 多源关键词搜索
- 影片详情、多线路、多集数播放
- 播放地址自动解析（jx_url）
- 播放进度本地记忆（localStorage）
- 资源源本地 JSON 配置

## 技术栈

- **Next.js 15** (App Router)
- **TypeScript**
- **Tailwind CSS 4**
- **ArtPlayer + hls.js** 播放器
- **axios** 请求 MacCMS 采集 API

## 快速开始

```bash
npm install
npm run dev
```

访问 http://localhost:3000

## 配置资源源

编辑 [`config/sources.json`](config/sources.json)：

```json
{
  "id": 1,
  "name": "光速",
  "url": "https://api.guangsuapi.com/api.php/provide/vod/",
  "flag": 0,
  "jx_url": "https://www.playm3u8.cn/jiexi.php?url=",
  "vip_only": false
}
```

| 字段 | 说明 |
|------|------|
| `flag` | `0` 启用，`-1` 禁用 |
| `url` | MacCMS 采集 API 根地址 |
| `jx_url` | 播放解析接口（可选） |

## API 接口

| 路径 | 说明 |
|------|------|
| `GET /api/sources` | 可用资源源列表 |
| `GET /api/vod/list?sourceId=&pg=` | 影片列表 |
| `GET /api/vod/detail?sourceId=&ids=` | 影片详情 |
| `GET /api/vod/search?wd=` | 搜索（多源聚合） |
| `GET /api/play/parse?sourceId=&url=` | 解析播放地址 |

## 目录结构

```
app/           # 页面与 API Routes
components/    # UI 组件
lib/           # MacCMS 客户端、解析器
config/        # 资源源配置
public/        # 静态资源
```

## 说明

- 第三方采集站可能不稳定，需自行维护 `config/sources.json`
- 仅供个人学习研究使用
