#!/usr/bin/env python3
"""
打印飞书多维表格的全部字段定义 + 全部行数据。
用法：
    python3 scripts/feishu_dump.py                  # 打印 "CoinFlow 账单" 那张表（按名字匹配）
    python3 scripts/feishu_dump.py <app_token>      # 指定 app_token
"""
import sys, json, urllib.request, urllib.parse, urllib.error, plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLIST = ROOT / "CoinFlow/Config/Config.plist"
with PLIST.open("rb") as f:
    cfg = plistlib.load(f)
APP_ID, APP_SECRET = cfg.get("Feishu_App_ID",""), cfg.get("Feishu_App_Secret","")
if not APP_ID or not APP_SECRET:
    print("❌ Config.plist 缺少 Feishu_App_ID / Feishu_App_Secret"); sys.exit(1)

HOST = "https://open.feishu.cn"

def http(method, path, body=None, token=None):
    url = HOST + path
    data = json.dumps(body or {}).encode("utf-8") if (body is not None or method == "POST") else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json; charset=utf-8")
    if token: req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
    obj = json.loads(raw)
    if obj.get("code") != 0:
        print(f"❌ API err code={obj.get('code')} msg={obj.get('msg')} raw={raw[:300]}"); sys.exit(1)
    return obj.get("data", {})

def get_token():
    d = http("POST", "/open-apis/auth/v3/tenant_access_token/internal",
             body={"app_id": APP_ID, "app_secret": APP_SECRET})
    # 该接口 data 在顶层，不在 data 字段下；手动再来一次
    url = HOST + "/open-apis/auth/v3/tenant_access_token/internal"
    req = urllib.request.Request(url,
            data=json.dumps({"app_id": APP_ID, "app_secret": APP_SECRET}).encode("utf-8"),
            method="POST")
    req.add_header("Content-Type", "application/json; charset=utf-8")
    with urllib.request.urlopen(req, timeout=10) as r:
        obj = json.loads(r.read().decode("utf-8"))
    return obj["tenant_access_token"]

def find_coinflow_app_token(token):
    d = http("GET", "/open-apis/drive/v1/files?order_by=EditedTime&direction=DESC&page_size=50", token=token)
    for f in d.get("files", []):
        if f.get("type") == "bitable" and f.get("name") == "CoinFlow 账单":
            return f["token"], f.get("url", "")
    print("❌ 未找到名为 'CoinFlow 账单' 的多维表格"); sys.exit(1)

def text_of(v):
    """文本字段在读接口返回 [{'text':'...', 'type':'text'}] 格式；SingleSelect 返回字符串"""
    if isinstance(v, list):
        return "".join(x.get("text", "") if isinstance(x, dict) else str(x) for x in v)
    if isinstance(v, dict) and "text" in v:
        return v["text"]
    return v

def fmt_value(k, v):
    # 日期时间字段 → 可读时间
    if isinstance(v, (int, float)) and any(s in k for s in ["日期", "时间"]):
        from datetime import datetime
        return datetime.fromtimestamp(v/1000).strftime("%Y-%m-%d %H:%M:%S")
    return text_of(v)

def main():
    token = get_token()
    if len(sys.argv) > 1:
        app_token = sys.argv[1]
        url = f"https://my.feishu.cn/base/{app_token}"
    else:
        app_token, url = find_coinflow_app_token(token)
    print(f"📋 表: CoinFlow 账单")
    print(f"   app_token={app_token}")
    print(f"   url={url}")

    # 数据表
    d = http("GET", f"/open-apis/bitable/v1/apps/{app_token}/tables", token=token)
    tables = d.get("items", [])
    if not tables:
        print("❌ 无数据表"); sys.exit(1)
    table_id = tables[0]["table_id"]
    table_name = tables[0].get("name", "")
    print(f"   data_table={table_name} (table_id={table_id})")
    print()

    # 字段定义
    print("═══ 字段定义 ═══")
    d = http("GET", f"/open-apis/bitable/v1/apps/{app_token}/tables/{table_id}/fields", token=token)
    fields = d.get("items", [])
    print(f"字段数: {len(fields)}")
    for i, f in enumerate(fields, 1):
        pk = "[主键]" if f.get("is_primary") else ""
        print(f"  {i:2d}. {f['field_name']:12s}  type={f['type']}  ui_type={f.get('ui_type','')}  {pk}")
    print()

    # 行数据（分页）
    print("═══ 行数据 ═══")
    all_rows = []
    page_token = None
    while True:
        path = f"/open-apis/bitable/v1/apps/{app_token}/tables/{table_id}/records/search?page_size=200"
        if page_token:
            path += f"&page_token={urllib.parse.quote(page_token)}"
        d = http("POST", path, body={}, token=token)
        all_rows.extend(d.get("items", []))
        if not d.get("has_more") or not d.get("page_token"):
            break
        page_token = d.get("page_token")
    print(f"行数: {len(all_rows)}")
    print()
    for i, r in enumerate(all_rows, 1):
        print(f"── 行 {i} ── record_id={r.get('record_id')}")
        f = r.get("fields", {})
        if not f:
            print("  (空行 · 无任何字段值)")
            continue
        # 列名按字段定义顺序输出
        for fd in fields:
            name = fd["field_name"]
            if name in f:
                print(f"  {name}: {fmt_value(name, f[name])}")
        # 打印字段定义外的字段（比如主键等）
        known = {fd["field_name"] for fd in fields}
        for k, v in f.items():
            if k not in known:
                print(f"  {k}: {fmt_value(k, v)}")
        print()

if __name__ == "__main__":
    main()
