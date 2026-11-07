
if script.Enabled == true then
	local FX = script.Parent.Fire.Light.FX
	FX.Enabled = false
	script.Parent.Fire.Light.Range = 10
	script:Destroy()
end