# 数据统计接口文档

## 接口概述

`/api/data` 接口用于获取配额消耗统计数据，支持按时间单位（小时/天/周/月）聚合，可按模型分组或汇总统计。

## 接口地址

```
GET /api/data
```

## 认证方式

需要管理员权限，通过 Cookie 或 Session 认证。

## 请求参数

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `start_timestamp` | int64 | 是 | - | 开始时间戳（秒） |
| `end_timestamp` | int64 | 是 | - | 结束时间戳（秒） |
| `username` | string | 否 | 空 | 用户名，不传则统计所有用户 |
| `default_time` | string | 否 | `hour` | 时间单位：`hour`、`day`、`week`、`month` |
| `group_by_model` | string | 否 | `true` | 是否按模型分组：`true` 或 `false` |

### 参数说明

#### `default_time` 时间单位

| 值 | 说明 |
|---|------|
| `hour` | 按小时聚合（默认），返回原始小时粒度数据 |
| `day` | 按天聚合，以本地时区 00:00:00 为边界 |
| `week` | 按周聚合，以本地时区周一 00:00:00 为边界 |
| `month` | 按月聚合，以本地时区每月 1 日 00:00:00 为边界 |

#### `group_by_model` 分组方式

| 值 | 说明 |
|---|------|
| `true` | 按模型分组，每个模型单独统计（默认） |
| `false` | 不按模型分组，所有模型汇总统计，`model_name` 返回 `"all"` |

## 响应格式

### 成功响应

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "created_at": 1706313600,
      "model_name": "gpt-4",
      "token_used": 15000,
      "count": 50,
      "quota": 3000
    }
  ]
}
```

### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `created_at` | int64 | 时间戳（按时间单位取整后的值） |
| `model_name` | string | 模型名称，`group_by_model=false` 时为 `"all"` |
| `token_used` | int | Token 消耗总量 |
| `count` | int | 请求次数 |
| `quota` | int | 配额消耗（内部单位） |

### 错误响应

```json
{
  "success": false,
  "message": "无效的 time_unit 参数，可选值：hour、day、week、month"
}
```

## 请求示例

### 示例 1：按天统计所有用户的汇总数据

```bash
curl -X GET "https://your-api.com/api/data?start_timestamp=1706140800&end_timestamp=1706745600&default_time=day&group_by_model=false" \
  -H "Cookie: session=xxx"
```

**响应：**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "created_at": 1706140800,
      "model_name": "all",
      "token_used": 125000,
      "count": 500,
      "quota": 25000
    },
    {
      "created_at": 1706227200,
      "model_name": "all",
      "token_used": 98000,
      "count": 420,
      "quota": 19600
    }
  ]
}
```

### 示例 2：按周统计指定用户的模型分组数据

```bash
curl -X GET "https://your-api.com/api/data?start_timestamp=1704067200&end_timestamp=1706745600&username=john&default_time=week&group_by_model=true" \
  -H "Cookie: session=xxx"
```

**响应：**

```json
{
  "success": true,
  "message": "",
  "data": [
    {
      "created_at": 1704067200,
      "model_name": "gpt-4",
      "token_used": 50000,
      "count": 200,
      "quota": 10000
    },
    {
      "created_at": 1704067200,
      "model_name": "claude-3-opus",
      "token_used": 30000,
      "count": 100,
      "quota": 6000
    },
    {
      "created_at": 1704672000,
      "model_name": "gpt-4",
      "token_used": 45000,
      "count": 180,
      "quota": 9000
    }
  ]
}
```

### 示例 3：按月统计所有用户的模型分组数据

```bash
curl -X GET "https://your-api.com/api/data?start_timestamp=1701388800&end_timestamp=1706745600&default_time=month" \
  -H "Cookie: session=xxx"
```

## 时区处理

接口支持时区配置，通过环境变量 `DATA_EXPORT_TIMEZONE_OFFSET` 设置时区偏移（秒）。

- 默认值：`28800`（UTC+8，北京时间）
- 计算方式：`偏移秒数 = 时区小时 × 3600`

例如：
- UTC+8（北京）：`28800`
- UTC+0（伦敦）：`0`
- UTC-5（纽约）：`-18000`

## 数据库兼容性

接口支持以下数据库：

| 数据库 | 支持状态 |
|--------|----------|
| MySQL | ✅ 完全支持 |
| PostgreSQL | ✅ 完全支持 |
| SQLite | ✅ 完全支持 |

## 注意事项

1. **数据精度**：原始数据以小时为单位存储，更大时间单位的统计是聚合计算结果
2. **时间边界**：日/周/月的边界按本地时区计算，周以周一为起始
3. **性能考虑**：大时间范围查询建议使用更大的时间单位减少数据量
4. **权限要求**：此接口需要管理员权限

## 相关接口

### 用户个人统计接口

```
GET /api/user/data
```

此接口用于普通用户查看自己的消耗统计，时间跨度限制为 1 个月。

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
|--------|------|------|--------|------|
| `start_timestamp` | int64 | 是 | - | 开始时间戳（秒） |
| `end_timestamp` | int64 | 是 | - | 结束时间戳（秒） |
| `default_time` | string | 否 | `hour` | 时间单位：`hour`、`day`、`week`、`month` |

---

## 更新日志

### 2026-01-27

- 新增 `default_time` 参数，支持按 hour/day/week/month 聚合
- 新增 `group_by_model` 参数，支持汇总统计（不按模型分组）
- `username` 参数改为可选，不传则统计所有用户
- 支持 MySQL、PostgreSQL、SQLite 三种数据库
