core.register_fetches("leak_check", function(txn, var)
	local result = txn:get_var(var)
	
	if result == nil then
		return "<nil>"
	end
	
	return result
end)
