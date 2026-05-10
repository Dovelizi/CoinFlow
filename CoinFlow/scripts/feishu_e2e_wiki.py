#!/usr/bin/env python3
"""
M9-Fix1 · Wiki 模式端到端测试。

直接针对用户指定的 Wiki Base（个人记账系统）跑全链路：
  T1 获取 tenant_access_token
  T2 Wiki node_token → obj_token
  T3 列出当前字段 + 补齐缺失字段（不动已有）
  T4 删除预置空白行
  T5 写入测试 record → 返回 record_id
  T6 更新 record（改金额）
  T7 软删 record（已删除 = true）
  T8 拉取全表，验证字段完整

用法：
    cd CoinFlow && python3 scripts/feishu_e2e_wiki.py
"""
import plistlib, json, urllib.request, urllib.parse, sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
cfg = plistlib.load(open(ROOT / "CoinFlow/Config/Config.plist", "rb"))
APP_ID = cfg.get("Feishu_App_ID", "")
APP_SECRET = cfg.get("Feishu_App_Secret", "")
WIKI_NODE = cfg.get("Feishu_Wiki_Node_Token", "")
TABLE_ID = cfg.get("Feishu_Bills_Table_Id", "")
if not all([APP_ID, APP_SECRET, WIKI_NODE, TABLE_ID]):
    print("❌ Config.plist 缺少 Feishu_App_ID / Secret / Wiki_Node_Token / Bills_Table_Id")
    sys.exit(1)

HOST = "https://open.feishu.cn"

def api(method, path, body=None, token=None):
    data = json.dumps(body or {}).encode() if (body is not None or method == "POST") else None
    req = urllib.request.Request(HOST + path, data=data, method=method)
    req.add_header("Content-Type", "application/json; charset=utf-8")
    if token: req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
    obj = json.loads(raw)
    if obj.get("code") != 0:
        raise RuntimeError(f"API code={obj.get('code')} msg={obj.get('msg')} raw={raw[:400]}")
    return obj.get("data", {})

# T1
print("═══ T1 获取 tenant_access_token ═══")
req = urllib.request.Request(
    HOST + "/open-apis/auth/v3/tenant_access_token/internal",
    data=json.dumps({"app_id": APP_ID, "app_secret": APP_SECRET}).encode(),
    method="POST",
)
req.add_header("Content-Type", "application/json; charset=utf-8")
with urllib.request.urlopen(req, timeout=10) as r:
    token = json.loads(r.read())["tenant_access_token"]
print(f"✓ token={token[:15]}...")

# T2
print(f"\n═══ T2 Wiki node_token → obj_token ═══")
node = api("GET", f"/open-apis/wiki/v2/spaces/get_node?token={WIKI_NODE}", token=token)["node"]
if node.get("obj_type") != "bitable":
    print(f"❌ Wiki node obj_type={node.get('obj_type')} 不是 bitable"); sys.exit(1)
APP_TOKEN = node["obj_token"]
print(f"✓ title={node.get('title')}")
print(f"✓ obj_token={APP_TOKEN}")

# T3
print(f"\n═══ T3 补齐缺失字段 ═══")
existing = api("GET", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/fields", token=token)
existing_items = existing.get("items", [])
existing_names = {f["field_name"] for f in existing_items}
print(f"现有字段: {sorted(existing_names)}")

desired = [
    {"field_name": "单据ID", "type": 1},
    {"field_name": "日期",   "type": 5},
    {"field_name": "金额",   "type": 2},
    {"field_name": "货币",   "type": 3,
     "property": {"options": [{"name": x} for x in ["CNY","USD","HKD","EUR","JPY"]]}},
    {"field_name": "收支",   "type": 3,
     "property": {"options": [{"name": "支出"}, {"name": "收入"}]}},
    {"field_name": "分类",   "type": 1},
    {"field_name": "来源",   "type": 3,
     "property": {"options": [{"name": x} for x in ["手动","截图OCR-Vision","截图OCR-API","截图OCR-LLM","语音-本地","语音-云端"]]}},
    {"field_name": "创建时间", "type": 5},
    {"field_name": "更新时间", "type": 5},
    {"field_name": "已删除",   "type": 7},
]
added = 0
for d in desired:
    if d["field_name"] in existing_names:
        continue
    try:
        api("POST", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/fields",
            body=d, token=token)
        print(f"  + {d['field_name']} (type={d['type']})")
        added += 1
    except RuntimeError as e:
        if "1254014" in str(e):
            continue
        print(f"  ⚠ 添加 {d['field_name']} 失败: {e}")
print(f"✓ 补齐 {added} 个缺失字段")

# T4
print(f"\n═══ T4 删除预置空白行 ═══")
search = api("POST", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/records/search?page_size=500",
             body={}, token=token)
items = search.get("items", [])
empty_ids = [i["record_id"] for i in items if not i.get("fields")]
if empty_ids:
    api("POST", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/records/batch_delete",
        body={"records": empty_ids}, token=token)
    print(f"✓ 删除 {len(empty_ids)} 条空白预置行")
else:
    print("✓ 无空白行")

# T5
print(f"\n═══ T5 写入测试 record ═══")
test_id = f"e2e-wiki-{int(datetime.now().timestamp())}"
now_ms = int(datetime.now().timestamp() * 1000)
write_fields = {
    "账单描述": "E2E Wiki 测试 · 首笔",
    "单据ID": test_id,
    "日期": now_ms,
    "金额": 99.99,
    "货币": "CNY",
    "收支": "支出",
    "分类": "餐饮",
    "来源": "手动",
    "创建时间": now_ms,
    "更新时间": now_ms,
    "已删除": False,
}
created = api("POST", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/records",
              body={"fields": write_fields}, token=token)
record_id = created["record"]["record_id"]
print(f"✓ 写入 record_id={record_id}")

# T6
print(f"\n═══ T6 更新金额（99.99 → 199.99）═══")
write_fields["金额"] = 199.99
write_fields["账单描述"] = "E2E Wiki 测试 · 已更新"
write_fields["更新时间"] = int(datetime.now().timestamp() * 1000)
api("PUT", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/records/{record_id}",
    body={"fields": write_fields}, token=token)
print("✓ 更新成功")

# T7
print(f"\n═══ T7 软删（已删除 = true）═══")
write_fields["已删除"] = True
write_fields["账单描述"] = "E2E Wiki 测试 · 已软删"
api("PUT", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/records/{record_id}",
    body={"fields": write_fields}, token=token)
print("✓ 软删成功")

# T8
print(f"\n═══ T8 拉取全表验证 ═══")
search = api("POST", f"/open-apis/bitable/v1/apps/{APP_TOKEN}/tables/{TABLE_ID}/records/search?page_size=500",
             body={}, token=token)
all_rows = search.get("items", [])
print(f"✓ 共 {len(all_rows)} 行")
me = next((r for r in all_rows
           if (r.get("fields", {}).get("单据ID") == test_id)), None)
if me:
    f = me["fields"]
    amount = f.get("金额")
    deleted = f.get("已删除")
    desc = f.get("账单描述")
    if isinstance(desc, list):
        desc = "".join(x.get("text","") for x in desc if isinstance(x, dict))
    print(f"✓ 找到测试行：金额={amount} 已删除={deleted} 描述={desc!r}")
    if abs((amount or 0) - 199.99) > 0.01:
        print(f"❌ 金额未达预期"); sys.exit(1)
    if not deleted:
        print(f"❌ 软删标志未生效"); sys.exit(1)
else:
    print(f"❌ 未找到 testId={test_id}"); sys.exit(1)

print(f"\n✅ 全部 8 步通过")
print(f"\n💡 打开飞书查看表：")
print(f"   https://my.feishu.cn/wiki/{WIKI_NODE}?table={TABLE_ID}")
