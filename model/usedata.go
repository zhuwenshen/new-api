package model

import (
	"fmt"
	"sync"
	"time"

	"github.com/QuantumNous/new-api/common"
	"gorm.io/gorm"
)

// QuotaData 柱状图数据
type QuotaData struct {
	Id        int    `json:"id"`
	UserID    int    `json:"user_id" gorm:"index"`
	Username  string `json:"username" gorm:"index:idx_qdt_model_user_name,priority:2;size:64;default:''"`
	ModelName string `json:"model_name" gorm:"index:idx_qdt_model_user_name,priority:1;size:64;default:''"`
	CreatedAt int64  `json:"created_at" gorm:"bigint;index:idx_qdt_created_at,priority:2"`
	TokenUsed int    `json:"token_used" gorm:"default:0"`
	Count     int    `json:"count" gorm:"default:0"`
	Quota     int    `json:"quota" gorm:"default:0"`
}

func UpdateQuotaData() {
	for {
		if common.DataExportEnabled {
			common.SysLog("正在更新数据看板数据...")
			SaveQuotaDataCache()
		}
		time.Sleep(time.Duration(common.DataExportInterval) * time.Minute)
	}
}

var CacheQuotaData = make(map[string]*QuotaData)
var CacheQuotaDataLock = sync.Mutex{}

func logQuotaDataCache(userId int, username string, modelName string, quota int, createdAt int64, tokenUsed int) {
	key := fmt.Sprintf("%d-%s-%s-%d", userId, username, modelName, createdAt)
	quotaData, ok := CacheQuotaData[key]
	if ok {
		quotaData.Count += 1
		quotaData.Quota += quota
		quotaData.TokenUsed += tokenUsed
	} else {
		quotaData = &QuotaData{
			UserID:    userId,
			Username:  username,
			ModelName: modelName,
			CreatedAt: createdAt,
			Count:     1,
			Quota:     quota,
			TokenUsed: tokenUsed,
		}
	}
	CacheQuotaData[key] = quotaData
}

func LogQuotaData(userId int, username string, modelName string, quota int, createdAt int64, tokenUsed int) {
	// 只精确到小时
	createdAt = createdAt - (createdAt % 3600)

	CacheQuotaDataLock.Lock()
	defer CacheQuotaDataLock.Unlock()
	logQuotaDataCache(userId, username, modelName, quota, createdAt, tokenUsed)
}

func SaveQuotaDataCache() {
	CacheQuotaDataLock.Lock()
	defer CacheQuotaDataLock.Unlock()
	size := len(CacheQuotaData)
	// 如果缓存中有数据，就保存到数据库中
	// 1. 先查询数据库中是否有数据
	// 2. 如果有数据，就更新数据
	// 3. 如果没有数据，就插入数据
	for _, quotaData := range CacheQuotaData {
		quotaDataDB := &QuotaData{}
		DB.Table("quota_data").Where("user_id = ? and username = ? and model_name = ? and created_at = ?",
			quotaData.UserID, quotaData.Username, quotaData.ModelName, quotaData.CreatedAt).First(quotaDataDB)
		if quotaDataDB.Id > 0 {
			//quotaDataDB.Count += quotaData.Count
			//quotaDataDB.Quota += quotaData.Quota
			//DB.Table("quota_data").Save(quotaDataDB)
			increaseQuotaData(quotaData.UserID, quotaData.Username, quotaData.ModelName, quotaData.Count, quotaData.Quota, quotaData.CreatedAt, quotaData.TokenUsed)
		} else {
			DB.Table("quota_data").Create(quotaData)
		}
	}
	CacheQuotaData = make(map[string]*QuotaData)
	common.SysLog(fmt.Sprintf("保存数据看板数据成功，共保存%d条数据", size))
}

func increaseQuotaData(userId int, username string, modelName string, count int, quota int, createdAt int64, tokenUsed int) {
	err := DB.Table("quota_data").Where("user_id = ? and username = ? and model_name = ? and created_at = ?",
		userId, username, modelName, createdAt).Updates(map[string]interface{}{
		"count":      gorm.Expr("count + ?", count),
		"quota":      gorm.Expr("quota + ?", quota),
		"token_used": gorm.Expr("token_used + ?", tokenUsed),
	}).Error
	if err != nil {
		common.SysLog(fmt.Sprintf("increaseQuotaData error: %s", err))
	}
}

func GetQuotaDataByUsername(username string, startTime int64, endTime int64) (quotaData []*QuotaData, err error) {
	var quotaDatas []*QuotaData
	// 从quota_data表中查询数据
	err = DB.Table("quota_data").Where("username = ? and created_at >= ? and created_at <= ?", username, startTime, endTime).Find(&quotaDatas).Error
	return quotaDatas, err
}

func GetQuotaDataByUserId(userId int, startTime int64, endTime int64) (quotaData []*QuotaData, err error) {
	var quotaDatas []*QuotaData
	// 从quota_data表中查询数据
	err = DB.Table("quota_data").Where("user_id = ? and created_at >= ? and created_at <= ?", userId, startTime, endTime).Find(&quotaDatas).Error
	return quotaDatas, err
}

// GetQuotaDataByUserIdWithTimeUnit 根据用户ID和时间单位获取聚合数据
func GetQuotaDataByUserIdWithTimeUnit(userId int, startTime int64, endTime int64, timeUnit string) (quotaData []*QuotaData, err error) {
	var timeGroupExpr string
	tzOffset := common.DataExportTimezoneOffset
	// 周一偏移：1970-01-01 是周四，需要加 3 天（259200 秒）让周从周一开始
	const mondayOffset = 3 * 86400

	// 根据不同数据库和时间单位生成分组表达式
	// 时区处理：先加上时区偏移，计算后再减去，得到本地时区的日期边界对应的 UTC 时间戳
	switch timeUnit {
	case "day":
		if common.UsingMySQL {
			timeGroupExpr = fmt.Sprintf("((created_at + %d) DIV 86400) * 86400 - %d", tzOffset, tzOffset)
		} else {
			// PostgreSQL 和 SQLite 都使用 / 进行整数除法
			timeGroupExpr = fmt.Sprintf("((created_at + %d) / 86400) * 86400 - %d", tzOffset, tzOffset)
		}
	case "week":
		// 周从周一开始：加上周一偏移后计算，再减去偏移
		if common.UsingMySQL {
			timeGroupExpr = fmt.Sprintf("((created_at + %d + %d) DIV 604800) * 604800 - %d - %d", tzOffset, mondayOffset, mondayOffset, tzOffset)
		} else {
			timeGroupExpr = fmt.Sprintf("((created_at + %d + %d) / 604800) * 604800 - %d - %d", tzOffset, mondayOffset, mondayOffset, tzOffset)
		}
	case "month":
		if common.UsingPostgreSQL {
			timeGroupExpr = fmt.Sprintf("EXTRACT(EPOCH FROM DATE_TRUNC('month', TO_TIMESTAMP(created_at + %d))) - %d", tzOffset, tzOffset)
		} else if common.UsingSQLite {
			timeGroupExpr = fmt.Sprintf("CAST(STRFTIME('%%s', DATE(created_at + %d, 'unixepoch', 'start of month')) AS INTEGER) - %d", tzOffset, tzOffset)
		} else {
			timeGroupExpr = fmt.Sprintf("UNIX_TIMESTAMP(DATE_FORMAT(FROM_UNIXTIME(created_at + %d), '%%Y-%%m-01')) - %d", tzOffset, tzOffset)
		}
	default:
		// hour - 默认按小时，直接返回原始数据
		var quotaDatas []*QuotaData
		err = DB.Table("quota_data").Where("user_id = ? and created_at >= ? and created_at <= ?", userId, startTime, endTime).Find(&quotaDatas).Error
		return quotaDatas, err
	}

	var quotaDatas []*QuotaData
	err = DB.Table("quota_data").
		Select(fmt.Sprintf("model_name, SUM(count) as count, SUM(quota) as quota, SUM(token_used) as token_used, %s as created_at", timeGroupExpr)).
		Where("user_id = ? AND created_at >= ? AND created_at <= ?", userId, startTime, endTime).
		Group(fmt.Sprintf("model_name, %s", timeGroupExpr)).
		Order("created_at ASC").
		Find(&quotaDatas).Error
	return quotaDatas, err
}

func GetAllQuotaDates(startTime int64, endTime int64, username string, timeUnit string) (quotaData []*QuotaData, err error) {
	var timeGroupExpr string
	tzOffset := common.DataExportTimezoneOffset
	// 周一偏移：1970-01-01 是周四，需要加 3 天（259200 秒）让周从周一开始
	const mondayOffset = 3 * 86400

	// 根据不同数据库和时间单位生成分组表达式
	// 时区处理：先加上时区偏移，计算后再减去，得到本地时区的日期边界对应的 UTC 时间戳
	switch timeUnit {
	case "day":
		if common.UsingMySQL {
			timeGroupExpr = fmt.Sprintf("((created_at + %d) DIV 86400) * 86400 - %d", tzOffset, tzOffset)
		} else {
			// PostgreSQL 和 SQLite 都使用 / 进行整数除法
			timeGroupExpr = fmt.Sprintf("((created_at + %d) / 86400) * 86400 - %d", tzOffset, tzOffset)
		}
	case "week":
		// 周从周一开始：加上周一偏移后计算，再减去偏移
		if common.UsingMySQL {
			timeGroupExpr = fmt.Sprintf("((created_at + %d + %d) DIV 604800) * 604800 - %d - %d", tzOffset, mondayOffset, mondayOffset, tzOffset)
		} else {
			timeGroupExpr = fmt.Sprintf("((created_at + %d + %d) / 604800) * 604800 - %d - %d", tzOffset, mondayOffset, mondayOffset, tzOffset)
		}
	case "month":
		if common.UsingPostgreSQL {
			timeGroupExpr = fmt.Sprintf("EXTRACT(EPOCH FROM DATE_TRUNC('month', TO_TIMESTAMP(created_at + %d))) - %d", tzOffset, tzOffset)
		} else if common.UsingSQLite {
			timeGroupExpr = fmt.Sprintf("CAST(STRFTIME('%%s', DATE(created_at + %d, 'unixepoch', 'start of month')) AS INTEGER) - %d", tzOffset, tzOffset)
		} else {
			timeGroupExpr = fmt.Sprintf("UNIX_TIMESTAMP(DATE_FORMAT(FROM_UNIXTIME(created_at + %d), '%%Y-%%m-01')) - %d", tzOffset, tzOffset)
		}
	default:
		// hour - 默认按小时
		timeGroupExpr = "created_at"
	}

	var quotaDatas []*QuotaData
	query := DB.Table("quota_data").
		Select(fmt.Sprintf("model_name, SUM(count) as count, SUM(quota) as quota, SUM(token_used) as token_used, %s as created_at", timeGroupExpr)).
		Where("created_at >= ? AND created_at <= ?", startTime, endTime)

	if username != "" {
		query = query.Where("username = ?", username)
	}

	err = query.Group(fmt.Sprintf("model_name, %s", timeGroupExpr)).Order("created_at ASC").Find(&quotaDatas).Error
	return quotaDatas, err
}

// QuotaStatResult 统计结果结构体（不按模型分组）
type QuotaStatResult struct {
	CreatedAt int64  `json:"created_at"` // 时间戳（按时间单位取整后的值）
	ModelName string `json:"model_name"` // 模型名称，统一为 "all"
	TokenUsed int    `json:"token_used"`
	Count     int    `json:"count"`
	Quota     int    `json:"quota"`
}

// GetQuotaStats 获取按时间单位聚合的统计数据
// timeUnit: hour, day, week, month
// username: 可选，为空则统计所有用户
func GetQuotaStats(startTime int64, endTime int64, username string, timeUnit string) (results []*QuotaStatResult, err error) {
	var timeGroupExpr string
	tzOffset := common.DataExportTimezoneOffset
	// 周一偏移：1970-01-01 是周四，需要加 3 天（259200 秒）让周从周一开始
	const mondayOffset = 3 * 86400

	// 根据不同数据库和时间单位生成分组表达式
	// 时区处理：先加上时区偏移，计算后再减去，得到本地时区的日期边界对应的 UTC 时间戳
	switch timeUnit {
	case "day":
		// 86400 秒 = 1 天
		if common.UsingMySQL {
			timeGroupExpr = fmt.Sprintf("((created_at + %d) DIV 86400) * 86400 - %d", tzOffset, tzOffset)
		} else {
			// PostgreSQL 和 SQLite 都使用 / 进行整数除法
			timeGroupExpr = fmt.Sprintf("((created_at + %d) / 86400) * 86400 - %d", tzOffset, tzOffset)
		}
	case "week":
		// 604800 秒 = 1 周，周从周一开始
		if common.UsingMySQL {
			timeGroupExpr = fmt.Sprintf("((created_at + %d + %d) DIV 604800) * 604800 - %d - %d", tzOffset, mondayOffset, mondayOffset, tzOffset)
		} else {
			timeGroupExpr = fmt.Sprintf("((created_at + %d + %d) / 604800) * 604800 - %d - %d", tzOffset, mondayOffset, mondayOffset, tzOffset)
		}
	case "month":
		// 月份需要使用日期函数，因为每月天数不同
		if common.UsingPostgreSQL {
			timeGroupExpr = fmt.Sprintf("EXTRACT(EPOCH FROM DATE_TRUNC('month', TO_TIMESTAMP(created_at + %d))) - %d", tzOffset, tzOffset)
		} else if common.UsingSQLite {
			timeGroupExpr = fmt.Sprintf("CAST(STRFTIME('%%s', DATE(created_at + %d, 'unixepoch', 'start of month')) AS INTEGER) - %d", tzOffset, tzOffset)
		} else {
			// MySQL
			timeGroupExpr = fmt.Sprintf("UNIX_TIMESTAMP(DATE_FORMAT(FROM_UNIXTIME(created_at + %d), '%%Y-%%m-01')) - %d", tzOffset, tzOffset)
		}
	default:
		// hour - 默认按小时，数据本身就是小时精度
		timeGroupExpr = "created_at"
	}

	query := DB.Table("quota_data").
		Select(fmt.Sprintf("%s as created_at, 'all' as model_name, SUM(token_used) as token_used, SUM(count) as count, SUM(quota) as quota", timeGroupExpr)).
		Where("created_at >= ? AND created_at <= ?", startTime, endTime)

	if username != "" {
		query = query.Where("username = ?", username)
	}

	err = query.Group(timeGroupExpr).Order("created_at ASC").Find(&results).Error
	return results, err
}
