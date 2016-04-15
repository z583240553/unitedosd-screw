local _M = {}
local bit = require "bit"
local cjson = require "cjson.safe"
local Json = cjson.encode

local strload

--Json的Key，用于协议帧头的几个数据
local cmds = {
  [0] = "length",
  [1] = "DTU_time",
  [2] = "DTU_status",
  [3] = "DTU_function",
  [4] = "device_address"
}

--Json的Key，用于清洁车云端显示状态
local status_cmds = {
  [1] = "Socket1_TotalActivePower",     --有功总电量
  [2] = "Socket2_TotalActivePower",           	--电压
  [3] = "Socket3_TotalActivePower",           	--电流
  [4] = "Socket4_TotalActivePower",       	--有功功率
  [5] = "Socket5_TotalActivePower",       	    --当前状态
  [6] = "Socket6_TotalActivePower",     --有功总电量
  [7] = "Socket1_Voltage",           	--电压
  [8] = "Socket2_Voltage",           	--电流
  [9] = "Socket3_Voltage",       	--有功功率
  [10] = "Socket4_Voltage",       	    --当前状态
  [11] = "Socket5_Voltage",     --有功总电量
  [12] = "Socket6_Voltage",           	--电压
  [13] = "Socket1_Current",           	--电流
  [14] = "Socket2_Current",       	--有功功率
  [15] = "Socket3_Current",       	    --当前状态
  [16] = "Socket4_Current",     --有功总电量
  [17] = "Socket5_Current",           	--电压
  [18] = "Socket6_Current",           	--电流
  [19] = "Socket1_ActivePower",       	--有功功率
  [20] = "Socket2_ActivePower",       	    --当前状态
  [21] = "Socket3_ActivePower",     --有功总电量
  [22] = "Socket4_ActivePower",           	--电压
  [23] = "Socket5_ActivePower",           	--电流
  [24] = "Socket6_ActivePower",       	--有功功率
  [25] = "Socket1_RunState",       	    --当前状态
  [26] = "Socket2_RunState",     --有功总电量
  [27] = "Socket3_RunState",           	--电压
  [28] = "Socket4_RunState",           	--电流
  [29] = "Socket5_RunState",       	--有功功率
  [30] = "Socket6_RunState",       	    --当前状态
  [31] = "Socket1_CommState",       	    --当前状态
  [32] = "Socket2_CommState",     --有功总电量
  [33] = "Socket3_CommState",           	--电压
  [34] = "Socket4_CommState",           	--电流
  [35] = "Socket5_CommState",       	--有功功率
  [36] = "Socket6_CommState",       	    --当前状态
}

--FCS校验
function utilCalcFCS( pBuf , len )
  local rtrn = 0
  local l = len

  while (len ~= 0)
    do
    len = len - 1
    rtrn = bit.bxor( rtrn , pBuf[l-len] )
  end

  return rtrn
end

--将字符转换为数字
function getnumber( index )
   return string.byte(strload,index)
end

--编码 /in 频道的数据包
function _M.encode(payload)
  return payload
end

--解码 /out 频道的数据包
function _M.decode(payload)
	local packet = {['status']='not'}

	--FCS校验的数组(table)，用于逐个存储每个Byte的数值
	local FCS_Array = {}

	--用来直接读取发来的数值，并进行校验
	local FCS_Value = 0

	--strload是全局变量，唯一的作用是在getnumber函数中使用
	strload = payload

	--前2个Byte是帧头，正常情况应该为';'和'1'
	local head1 = getnumber(1)
	local head2 = getnumber(2)

	--当帧头符合，才进行其他位的解码工作
	if ( (head1 == 0x3B) and (head2 == 0x31) ) then

		--数据长度
		local templen = bit.lshift( getnumber(3) , 8 ) + getnumber(4)

		FCS_Value = bit.lshift( getnumber(templen+5) , 8 ) + getnumber(templen+6)

		--将全部需要进行FCS校验的Byte写入FCS_Array这个table中
		for i=1,templen+4,1 do
			table.insert(FCS_Array,getnumber(i))
		end

		--进行FCS校验，如果计算值与读取指相等，则此包数据有效；否则弃之
		if(utilCalcFCS(FCS_Array,#FCS_Array) == FCS_Value) then
			packet['status'] = 'SUCCESS'
		else
			packet = {}
			packet['status'] = 'FCS-ERROR'
			return Json(packet)
		end

		--数据长度
		--packet[ cmds[0] ] = templen
		--运行时长
		packet[ cmds[1] ] = bit.lshift( getnumber(5) , 24 ) + bit.lshift( getnumber(6) , 16 ) + bit.lshift( getnumber(7) , 8 ) + getnumber(8)
		--采集模式
		--[[local mode = getnumber(9)
		if mode == 1 then
			packet[ cmds[2] ] = 'Mode-485'
			else
			packet[ cmds[2] ] = 'Mode-232'
		end--]]
		--func为判断是 实时数据/参数/故障 的参数
		local func = getnumber(10)
		if func == 1 then  --解析电量数据
			--packet[ cmds[3] ] = 'func-status'
			--设备modbus地址
			--packet[ cmds[4] ] = getnumber(11)

			--依次读入上传的数据
			--有功总电量
			for i=0,5 do
				packet[status_cmds[i+1]] = (bit.lshift( getnumber(12+i*4) , 24 ) + bit.lshift( getnumber(13+i*4) , 16 ) + bit.lshift( getnumber(14+i*4) , 8 ) + getnumber(15+i*4))/10
			end
			--电压
			for i=0,5 do
				packet[status_cmds[i+7]] = (bit.lshift( getnumber(36+i*2) , 8 ) + getnumber(37+i*2))/10
			end
			--电流
			for i=0,5 do
				packet[status_cmds[i+13]] = (bit.lshift( getnumber(48+i*2) , 8 ) + getnumber(49+i*2))/100
			end
			--有功功率
			for i=0,5 do
				packet[status_cmds[i+19]] = bit.lshift( getnumber(60+i*2) , 8 ) + getnumber(61+i*2)
			end
			--运行状态
			for i=0,5 do
				local x = bit.band(getnumber(72),bit.lshift(1,i))
				if(x == 0) then 
	               packet[status_cmds[i+25]] = 0
	            else
	               packet[status_cmds[i+25]] = 1
	            end 
			end
			--通讯状态
			for i=0,5 do
				local y = bit.band(getnumber(73),bit.lshift(1,i))
				if(y == 0) then 
	               packet[status_cmds[i+31]] = 0
	            else
	               packet[status_cmds[i+31]] = 1
	            end 
			end
		end

	else
		packet['head_error'] = 'error'
	end

	return Json(packet)
end

return _M
