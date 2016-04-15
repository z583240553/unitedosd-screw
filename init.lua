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

--Json的Key，用于螺杆机状态 ScrewMachine_State 对应螺杆机云端显示表
local status_cmds = {
  [1] = "ScrewMachine_State_01",
  [2] = "ScrewMachine_State_02",
  [3] = "ScrewMachine_State_03",
  [4] = "ScrewMachine_State_04",
  [5] = "ScrewMachine_State_05",
  [6] = "ScrewMachine_State_06",
  [7] = "ScrewMachine_State_07",
  [8] = "ScrewMachine_State_08",
  [9] = "ScrewMachine_State_09",
  [10] = "ScrewMachine_State_10",
  [11] = "ScrewMachine_State_11",
  [12] = "ScrewMachine_State_12",
  [13] = "ScrewMachine_State_13",
  [14] = "ScrewMachine_State_14",
  [15] = "ScrewMachine_State_15",
  [16] = "ScrewMachine_State_16",
  [17] = "ScrewMachine_State_17",
  [18] = "ScrewMachine_State_18",
  [19] = "ScrewMachine_State_19",
  [20] = "ScrewMachine_State_20",
  [21] = "ScrewMachine_State_21",
  [22] = "ScrewMachine_State_22",
  [23] = "ScrewMachine_State_23",
  [24] = "ScrewMachine_State_24",
  [25] = "ScrewMachine_State_25",
  [26] = "ScrewMachine_State_26",
  [27] = "ScrewMachine_State_27",
  [28] = "ScrewMachine_State_28",
  [29] = "ScrewMachine_State_29",
  [30] = "ScrewMachine_State_30",
  [31] = "ScrewMachine_State_31",
  [32] = "ScrewMachine_State_32",
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
	--packet['payload'] = strload
	--packet['payload11'] = getnumber(1)
	--packet['payload22'] = getnumber(2)
	--packet['payload33'] = getnumber(3)
	--packet['payload44'] = getnumber(4)
	--packet['payload55'] = getnumber(5)
	--packet['payload66'] = getnumber(6)
	--packet['payload77'] = getnumber(7)
	--packet['payload88'] = getnumber(8)
	--packet['payload99'] = getnumber(9)
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
		packet[ cmds[0] ] = templen
		--运行时长
		packet[ cmds[1] ] = bit.lshift( getnumber(5) , 24 ) + bit.lshift( getnumber(6) , 16 ) + bit.lshift( getnumber(7) , 8 ) + getnumber(8)
		--采集模式
		local mode = getnumber(9)
		if mode == 1 then
			packet[ cmds[2] ] = 'Mode-485'
			else
			packet[ cmds[2] ] = 'Mode-232'
		end
		--func为判断是 实时数据/参数/故障 的参数
		local func = getnumber(10)
		if func == 1 then  --解析状态数据
			packet[ cmds[3] ] = 'func-status'
			--设备modbus地址
			packet[ cmds[4] ] = getnumber(11)

			local databuff_table={} --用来暂存上传的实际状态数据
			local bitbuff_table={}  --用来暂存运行状态1/2的每位bit值

			--依次读入上传的数据
			for i=1,(templen-7)/2,1 do
				databuff_table[i] = bit.lshift( getnumber(10+i*2) , 8 ) + getnumber(11+i*2)
			end

			--将上传的数据转化为JSON格式数据 上传协议中前5个状态寄存器数据
			packet[ status_cmds[1] ] = databuff_table[1]/100
			packet[ status_cmds[2] ] = databuff_table[2]-20
			packet[ status_cmds[3] ] = databuff_table[3]
			packet[ status_cmds[4] ] = databuff_table[4]
			packet[ status_cmds[5] ] = databuff_table[5]/10

			--将上传的数据转化为JSON格式数据 上传协议中后5个状态寄存器数据
			for i=1,5,1 do
				packet[ status_cmds[5+i] ] = databuff_table[10+i]
			end

			--[[for j=0,1 do
				for i=0,7 do
					local y = bit.band(getnumber(26+j),bit.lshift(1,i))
					if(y == 0) then 
		               bitbuff_table[j*8+i+1] = 0
		            else
		               bitbuff_table[j*8+i+1] = 1
		            end 
				end
			end
			packet[ status_cmds[11] ] = bitbuff_table[1]
			packet[ status_cmds[12] ] = bitbuff_table[2]
			packet[ status_cmds[13] ] = bitbuff_table[4]
			packet[ status_cmds[14] ] = bitbuff_table[5]
			packet[ status_cmds[15] ] = bitbuff_table[6]
			packet[ status_cmds[16] ] = bitbuff_table[7]
			packet[ status_cmds[17] ] = bitbuff_table[8]
			packet[ status_cmds[18] ] = bitbuff_table[9]
			packet[ status_cmds[19] ] = bitbuff_table[10]
			packet[ status_cmds[20] ] = bitbuff_table[15]
			packet[ status_cmds[21] ] = bitbuff_table[16]
			]]
			--解析运行状态1(对应高字节databuff_table[26],低字节databuff_table[27])的每个bit位值
			for j=0,1 do
				for i=0,7 do
					local y = bit.band(getnumber(26+j),bit.lshift(1,i))
					if(y == 0) then 
		               bitbuff_table[j*8+i+1] = 0
		            else
		               bitbuff_table[j*8+i+1] = 1
		            end 
				end
			end
			--将运行状态1的每位bit值转化为JSON格式数据
			packet[ status_cmds[11] ] = bitbuff_table[1]
			packet[ status_cmds[12] ] = bitbuff_table[2]
			packet[ status_cmds[13] ] = bitbuff_table[4]
			packet[ status_cmds[14] ] = bitbuff_table[5]
			packet[ status_cmds[15] ] = bitbuff_table[6]
			packet[ status_cmds[16] ] = bitbuff_table[7]
			packet[ status_cmds[17] ] = bitbuff_table[8]
			packet[ status_cmds[18] ] = bitbuff_table[9]
			packet[ status_cmds[19] ] = bitbuff_table[10]
			packet[ status_cmds[20] ] = bitbuff_table[15]
			packet[ status_cmds[21] ] = bitbuff_table[16]

			--解析运行状态2(对应高字节databuff_table[28],低字节databuff_table[29])的每个bit位值
			for j=0,1 do
				for i=0,7 do
					local y = bit.band(getnumber(28+j),bit.lshift(1,i))
					if(y == 0) then 
		               bitbuff_table[j*8+i+1] = 0
		            else
		               bitbuff_table[j*8+i+1] = 1
		            end 
				end
			end
			--将运行状态2的每位bit值转化为JSON格式数据
			packet[ status_cmds[22] ] = bitbuff_table[1]
			packet[ status_cmds[23] ] = bitbuff_table[2]
			packet[ status_cmds[24] ] = bitbuff_table[4]
			packet[ status_cmds[25] ] = bitbuff_table[5]
			packet[ status_cmds[26] ] = bitbuff_table[6]
			packet[ status_cmds[27] ] = bitbuff_table[7]
			packet[ status_cmds[28] ] = bitbuff_table[8]
			packet[ status_cmds[29] ] = bitbuff_table[9]
			packet[ status_cmds[30] ] = bitbuff_table[14]
			packet[ status_cmds[31] ] = bitbuff_table[15]
			packet[ status_cmds[32] ] = bitbuff_table[16]
		end
	else
		packet['head_error'] = 'error'
	end
    
	return Json(packet)
end

return _M
