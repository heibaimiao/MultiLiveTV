# EHR663 影视 Demo

基于 EHR663 现成 Python 脚本的最小 Web Demo。不重写腾讯 / 优酷 / 爱奇艺 / 芒果接口。

## 启动

```bash
cd demos/ehr663-vod
python3 -m pip install -r requirements.txt
python3 app.py
```

浏览器打开 http://localhost:8000

首次启动若还没有 `demos/EHR663`，会自动 `git clone` 上游仓库。

## MacCMS 接口测速

从全部 EHR663 `py` 脚本抽取真实采集 API（`provide/vod`、`api_mac10.php` 等），测延迟后生成 TVBox `type:1` 源（`api` 不是 `.py`）：

```bash
cd demos/ehr663-vod
python3 latency_maccms.py              # 默认丢弃 >2000ms / 失败
python3 latency_maccms.py --max-ms 1500
```

输出：`maccms.json`。

接口说明：[`docs/ehr663-sources-api.md`](../../docs/ehr663-sources-api.md)。
