-- ~/.config/conky/sensors.lua
hwmon_map = {}
-- New cache table to store { value = "X", timestamp = 1234567 }
local cache = {}
local CACHE_DURATION = 9 -- Seconds

function conky_find_sensors()
    hwmon_map = {} 
    
    for i = 0, 15 do
        local path = "/sys/class/hwmon/hwmon" .. i
        local nf = io.open(path .. "/name", "r")
        
        if nf then
            local raw_name = nf:read("*all")
            nf:close()
            
            if raw_name then
                local dev_name = raw_name:gsub("\n", "")
                
                hwmon_map[dev_name] = {
                    index = i,
                    temp = {},
                    fan = {}
                }
                
                for s = 1, 15 do
                    local s_num = tostring(s)
                    for _, s_type in ipairs({"temp", "fan"}) do
                        local base_path = path .. "/" .. s_type .. s_num
                        
                        -- Check for input file (the actual sensor)
                        local ef = io.open(base_path .. "_input", "r")
                        if ef then
                            ef:close()
                            
                            -- FEATURE: Always map the numeric index as a key
                            hwmon_map[dev_name][s_type][s_num] = s_num
                            
                            -- Check for label file
                            local lf = io.open(base_path .. "_label", "r")
                            if lf then
                                local raw_lbl = lf:read("*all")
                                lf:close()
                                
                                if raw_lbl then
                                    -- Convert spaces to underscores
                                    local lbl = raw_lbl:gsub("\n", ""):gsub(" ", "_")
                                    -- Map the label to the sensor number
                                    hwmon_map[dev_name][s_type][lbl] = s_num
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function conky_get_hw_val(dev_name, s_type, key)
    if not hwmon_map or next(hwmon_map) == nil then 
        conky_find_sensors() 
    end
    
    local dev = hwmon_map[dev_name]
    if not dev then return "N/A" end
    
    local type_table = dev[s_type]
    if not type_table then return "N/A" end
    
    -- This works for BOTH labels ("Package_id_0") and raw indices ("1")
    local sensor_num = type_table[tostring(key)]
    if not sensor_num then return "N/A" end
    
    -- --- CACHING LOGIC ---
    local cache_key = dev_name .. s_type .. key
    local current_time = os.time()
    
    if cache[cache_key] and (current_time - cache[cache_key].timestamp < CACHE_DURATION) then
        return cache[cache_key].value
    end

    -- If no cache or cache expired, read fresh value
    local val = conky_parse("${hwmon " .. dev.index .. " " .. s_type .. " " .. sensor_num .. "}")
    
    -- Update cache
    cache[cache_key] = {
        value = val,
        timestamp = current_time
    }
    
    return val
end

-- --- COMPREHENSIVE DEBUG OUTPUT ---
conky_find_sensors()
print("\n" .. string.rep("=", 50))
print(string.format("%-20s | %-10s", "DEVICE", "PATH"))
print(string.rep("=", 50))

for name, data in pairs(hwmon_map) do
    print(string.format("%-20s | /sys/class/hwmon/hwmon%s", name, data.index))
    
    for _, s_type in ipairs({"temp", "fan"}) do
        local sensors = data[s_type]
        -- We sort keys to keep the output organized
        local sorted_keys = {}
        for k in pairs(sensors) do table.insert(sorted_keys, k) end
        table.sort(sorted_keys)

        for _, key in ipairs(sorted_keys) do
            local val = sensors[key]
            -- Only print the label-to-number mapping to avoid clutter
            -- If the key is a number, it's a raw sensor. If it's text, it's a label.
            if key:match("%D") then
                print(string.format("  [%-4s] %-25s -> sensor %s", s_type:upper(), key, val))
            else
                -- Only print the raw number if no label exists for this specific sensor number
                local has_label = false
                for k, v in pairs(sensors) do
                    if k:match("%D") and v == key then has_label = true break end
                end
                if not has_label then
                    print(string.format("  [%-4s] Sensor %-20s (No Label)", s_type:upper(), key))
                end
            end
        end
    end
    print(string.rep("-", 50))
end
