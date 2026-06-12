-- Copyright 2008 Yanira <forum-2008@email.de>
-- Licensed to the public under the Apache License 2.0.
--mod by wulishui 20191205

local uci = require "luci.model.uci".cursor()
local cport = uci:get_first("cupsd", "cupsd", "port") or 631

local m, s, o

local running=(luci.sys.call("pidof cupsd > /dev/null") == 0)

local button = ""
local state_msg = ""

if running then
        state_msg = "<b><font color=\"green\">" .. translate("～正在运行～") .. "</font></b>"
else
        state_msg = "<b><font color=\"red\">" .. translate("CUPS在睡觉觉zZZ") .. "</font></b>"
end

if running  then
	button = "<br/><br/>---<input class=\"cbi-button cbi-button-apply\" type=\"submit\" value=\" "..translate("打开管理界面").." \" onclick=\"window.open('http://'+window.location.hostname+':"..cport.."')\"/>---"
end

m = Map("cupsd", translate("CUPS打印服务器"))
m.description = translate("<font color=\"green\">CUPS是苹果公司为MacOS和其他类似UNIX的操作系统开发的基于标准的开源打印系统。</font>".. button  .. "<br/><br/>" .. translate("运行状态").. " : "  .. state_msg .. "<br />")

s = m:section(TypedSection, "cupsd", translate(""))
s.anonymous = true

s:option(Flag, "enabled", translate("Enable"))

o = s:option(Value, "port", translate("WEB管理端口"),translate("可随意设定为无冲突的端口，对程序运行无影响。"))
o.default = 631
o.rmempty = true

o = s:option(Flag, "airprint", translate("局域网发现 / AirPrint"), translate("通过 Avahi 发布已共享的 CUPS 打印机，让同一局域网内的 macOS、iOS 和支持 IPP 的客户端自动发现。"))
o.default = 1
o.rmempty = false

o = s:option(Button, "_refresh_airprint", translate("刷新局域网发现"), translate("在 CUPS 管理界面新增或修改打印机后，点击此按钮重新生成 Avahi 服务。"))
o.inputtitle = translate("刷新")
o.inputstyle = "apply"
function o.write(self, section)
	luci.sys.call("/etc/init.d/cupsd reload >/dev/null 2>&1")
end


return m
