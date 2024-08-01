-- Import menu elements
local menu = require("menu")

-- Inicializa as variáveis
local waypoints = {}
local plugin_enabled = false
local initialMessageDisplayed = false
local doorsEnabled = false
local interactedObjects = {}
local is_interacting = false
local interaction_end_time = 0
local ni = 1
local start_time = 0
local check_interval = 60 -- Tempo que ele vai entrar no mapa para explorar e ver se consegue cinders
local current_city_index = 1
local is_moving = false
local teleporting = false
local next_teleport_attempt_time = 0 -- Variável para a próxima tentativa de teleporte
local loading_start_time = nil -- Variável para marcar o início da tela de carregamento

-- Define padrões para nomes de objetos interativos
local interactive_patterns = { "usz_reward", "usz_rewardGizmo_" }

-- Tempo de expiração em segundos
local expiration_time = 10

-- Lista de cidades e waypoints
local helltide_tps = {
    {name = "Frac_Tundra_S", id = 0xACE9B, file = "menestad"},
    {name = "Scos_Coast", id = 0x27E01, file = "marowen"},
    {name = "Kehj_Oasis", id = 0xDEAFC, file = "ironwolfs"},
    {name = "Hawe_Verge", id = 0x9346B, file = "wejinhani"},
    {name = "Step_South", id = 0x462E2, file = "jirandai"}
}

-- Função para carregar waypoints do arquivo selecionado
local function load_waypoints(file)
    if file == "wejinhani" then
        waypoints = require("waypoints.wejinhani")
        console.print("Loaded waypoints: wejinhani")
    elseif file == "marowen" then
        waypoints = require("waypoints.marowen")
        console.print("Loaded waypoints: marowen")
    elseif file == "menestad" then
        waypoints = require("waypoints.menestad")
        console.print("Loaded waypoints: menestad")
    elseif file == "jirandai" then
        waypoints = require("waypoints.jirandai")
        console.print("Loaded waypoints: jirandai")
    elseif file == "ironwolfs" then
        waypoints = require("waypoints.ironwolfs")
        console.print("Loaded waypoints: ironwolfs")
    else
        console.print("No waypoints loaded")
    end
end

-- Função para verificar se o nome do objeto corresponde a algum padrão de interação
local function matchesAnyPattern(name)
    for _, pattern in ipairs(interactive_patterns) do
        if name:match(pattern) then
            return true
        end
    end
    return false
end

-- Função para mover o jogador até o objeto e interagir com ele
local function moveToAndInteract(obj)
    local player_pos = get_player_position()
    local obj_pos = obj:get_position()

    local distanceThreshold = 2.0 -- Distancia para interagir com o objto
    local moveThreshold = 12.0 -- Distancia maxima que ele localiza e se move ate o objeto

    local distance = obj_pos:dist_to(player_pos)
    
    if distance < distanceThreshold then
        is_interacting = true
        local obj_key = obj:get_skin_name() .. "_" .. obj:get_id()
        interactedObjects[obj_key] = os.clock() + expiration_time
        interact_object(obj)
        console.print("Interacting with " .. obj:get_skin_name())
        interaction_end_time = os.clock() + 5
        return true
    elseif distance < moveThreshold then
        pathfinder.request_move(obj_pos)
        return false
    end
end

-- Função para interagir com objetos
local function interactWithObjects()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    local objects = actors_manager.get_ally_actors()

    for _, obj in ipairs(objects) do
        if obj then
            local obj_id = obj:get_id()
            local obj_name = obj:get_skin_name()
            local obj_key = obj_name .. "_" .. obj_id

            if obj_name and matchesAnyPattern(obj_name) then
                if doorsEnabled and (not interactedObjects[obj_key] or os.clock() > interactedObjects[obj_key]) then
                    if moveToAndInteract(obj) then
                        return
                    end
                end
            end
        end
    end
end

-- Função para verificar se o jogador ainda está interagindo e retomar o movimento se necessário
local function checkInteraction()
    if is_interacting and os.clock() > interaction_end_time then
        is_interacting = false
        console.print("Interaction complete, resuming movement.")
    end
end

-- Função para verificar a cidade atual e carregar os waypoints
local function check_and_load_waypoints()
    local world_instance = world.get_current_world()
    if world_instance then
        local zone_name = world_instance:get_current_zone_name()

        for _, tp in ipairs(helltide_tps) do
            if zone_name == tp.name then
                load_waypoints(tp.file)
                current_city_index = tp.id -- Atualiza o índice da cidade atual
                return
            end
        end
        console.print("No matching city found for waypoints")
    end
end

-- Função para obter a distância entre o jogador e um ponto
local function get_distance(point)
    return get_player_position():dist_to(point)
end

-- Função de movimento principal
local function pulse()
    if not plugin_enabled or is_interacting or not is_moving then
        return
    end

    if ni > #waypoints or #waypoints == 0 then
        return
    end

    local current_waypoint = waypoints[ni]
    if get_distance(current_waypoint) < 1 then
        ni = ni + 1
    else
        pathfinder.request_move(current_waypoint)
    end
end

-- Função para verificar se o jogo está na tela de carregamento
local function is_loading_screen()
    local world_instance = world.get_current_world()
    if world_instance then
        local zone_name = world_instance:get_current_zone_name()
        return zone_name == nil or zone_name == ""
    end
    return true
end

-- Função para verificar se está na Helltide
local function is_in_helltide(local_player)
    local buffs = local_player:get_buffs()
    for _, buff in ipairs(buffs) do
        if buff.name_hash == 1066539 then -- ID do buff de Helltide
            return true
        end
    end
    return false
end

-- Função para iniciar a contagem de cinders e teletransporte
local function start_movement_and_check_cinders()
    if not is_moving then
        start_time = os.clock()
        is_moving = true
    end

    if os.clock() - start_time > check_interval then
        is_moving = false
        local cinders_count = get_helltide_coin_cinders()

        if cinders_count == 0 then
            console.print("No cinders found. Stopping movement to teleport.")
            local player_pos = get_player_position() -- Pega a posição atual do jogador
            pathfinder.request_move(player_pos) -- Move o jogador para sua posição atual para interromper o movimento
            
            if not is_loading_screen() then -- Verifica se não está na tela de carregamento antes de teleportar
                current_city_index = (current_city_index % #helltide_tps) + 1
                teleport_to_waypoint(helltide_tps[current_city_index].id)
                teleporting = true
                next_teleport_attempt_time = os.clock() + 15 -- Define a próxima tentativa de teleporte em 15 segundos
            else
                console.print("Currently in loading screen. Waiting before attempting teleport.")
                next_teleport_attempt_time = os.clock() + 10 -- Ajuste o tempo de espera se necessário
            end
        else
            console.print("Cinders found. Continuing movement.")
        end
    end

    pulse()
end

-- Função chamada periodicamente para interagir com objetos
on_update(function()
    if plugin_enabled then
        if teleporting then
            local current_time = os.clock()
            local current_world = world.get_current_world()
            if not current_world then
                return
            end

            -- Verifica se estamos na tela de loading (Limbo)
            if current_world:get_name():find("Limbo") then
                -- Se estamos no Limbo, define o início da tela de carregamento
                if not loading_start_time then
                    loading_start_time = current_time
                end
                return
            else
                -- Se estávamos no Limbo, mas agora não estamos, verifica se 4 segundos se passaram desde o início da tela de carregamento
                if loading_start_time and (current_time - loading_start_time) < 4 then
                    return
                end
                -- Reseta o tempo de início da tela de carregamento após esperar
                loading_start_time = nil
            end

            if not is_loading_screen() then -- Verifica se não está na tela de carregamento antes de tentar teletransportar
                local world_instance = world.get_current_world()
                if world_instance then
                    local zone_name = world_instance:get_current_zone_name()
                    if zone_name == helltide_tps[current_city_index].name then
                        load_waypoints(helltide_tps[current_city_index].file)
                        ni = 1 -- Resetar o índice do waypoint ao teletransportar
                        teleporting = false
                    elseif os.clock() > next_teleport_attempt_time then -- Verifica se é hora de tentar teleporte novamente
                        console.print("Teleport failed, retrying...")
                        teleport_to_waypoint(helltide_tps[current_city_index].id)
                        next_teleport_attempt_time = os.clock() + 30 -- Ajuste o tempo de espera se necessário
                    end
                end
            end
        else
            local local_player = get_local_player()
            if is_in_helltide(local_player) then
                checkInteraction()
                interactWithObjects()
                start_movement_and_check_cinders()
            else
                console.print("Not in Helltide zone. Attempting to teleport.")
                current_city_index = (current_city_index % #helltide_tps) + 1
                teleport_to_waypoint(helltide_tps[current_city_index].id)
                teleporting = true
                next_teleport_attempt_time = os.clock() + 15 -- Define a próxima tentativa de teleporte em 15 segundos
            end
        end
    end
end)

-- Função para renderizar o menu
on_render_menu(function()
    if menu.main_tree:push("HellChest Farmer (EletroLuz)-V1.0") then

        -- Renderiza o checkbox para habilitar o plugin de movimento
        local enabled = menu.plugin_enabled:get()
        if enabled ~= plugin_enabled then
            plugin_enabled = enabled
            if plugin_enabled then
                console.print("Movement Plugin enabled")
                check_and_load_waypoints() -- Verifica e carrega waypoints ao habilitar o plugin
            else
                console.print("Movement Plugin disabled")
            end
        end
        menu.plugin_enabled:render("Enable Movement Plugin", "Enable or disable the movement plugin")

        -- Renderiza o checkbox para habilitar o plugin de abertura de portas
        local enabled_doors = menu.main_openDoors_enabled:get() or false
        if enabled_doors ~= doorsEnabled then
            doorsEnabled = enabled_doors
            if doorsEnabled then
                console.print("Open Chests Plugin enabled")
            else
                console.print("Open Chests Plugin disabled")
            end
        end
        menu.main_openDoors_enabled:render("Open Chests", "Enable or disable the chest plugin")

        menu.main_tree:pop()
    end
end)