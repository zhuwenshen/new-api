package controller

import (
	"net/http"
	"strconv"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/model"

	"github.com/gin-gonic/gin"
)

// GetAllQuotaDates 获取统计数据
// 参数：
//   - start_timestamp: 开始时间戳（秒）
//   - end_timestamp: 结束时间戳（秒）
//   - username: 可选，指定用户名则只统计该用户
//   - time_unit: 可选，时间单位：hour（默认）、day、week、month
func GetAllQuotaDates(c *gin.Context) {
	startTimestamp, _ := strconv.ParseInt(c.Query("start_timestamp"), 10, 64)
	endTimestamp, _ := strconv.ParseInt(c.Query("end_timestamp"), 10, 64)
	username := c.Query("username")
	timeUnit := c.DefaultQuery("time_unit", "hour")

	// 验证 time_unit 参数
	validTimeUnits := map[string]bool{"hour": true, "day": true, "week": true, "month": true}
	if !validTimeUnits[timeUnit] {
		c.JSON(http.StatusOK, gin.H{
			"success": false,
			"message": "无效的 time_unit 参数，可选值：hour、day、week、month",
		})
		return
	}

	stats, err := model.GetQuotaStats(startTimestamp, endTimestamp, username, timeUnit)
	if err != nil {
		common.ApiError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "",
		"data":    stats,
	})
}

func GetUserQuotaDates(c *gin.Context) {
	userId := c.GetInt("id")
	startTimestamp, _ := strconv.ParseInt(c.Query("start_timestamp"), 10, 64)
	endTimestamp, _ := strconv.ParseInt(c.Query("end_timestamp"), 10, 64)
	// 判断时间跨度是否超过 1 个月
	if endTimestamp-startTimestamp > 2592000 {
		c.JSON(http.StatusOK, gin.H{
			"success": false,
			"message": "时间跨度不能超过 1 个月",
		})
		return
	}
	dates, err := model.GetQuotaDataByUserId(userId, startTimestamp, endTimestamp)
	if err != nil {
		common.ApiError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "",
		"data":    dates,
	})
	return
}
