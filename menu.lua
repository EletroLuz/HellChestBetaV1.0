-- Define a etiqueta do plugin
local plugin_label = "CAMINHADOR_PLUGIN_"

-- Cria os elementos do menu
local menu_elements = 
{
    plugin_enabled = checkbox:new(false, get_hash(plugin_label .. "plugin_enabled")),
    main_openDoors_enabled = checkbox:new(false, get_hash(plugin_label .. "main_openDoors_enabled")),
    main_tree = tree_node:new(0),
}

-- Função para renderizar o menu
function render_menu()
    menu_elements.main_tree:push("Helltide Farmer (EletroLuz)-V1.0")

    -- Renderiza o checkbox para habilitar o plugin de movimento
    menu_elements.plugin_enabled:render("Enable Movement Plugin", "Enable or disable the movement plugin")

    -- Renderiza o checkbox para habilitar o plugin de abertura de baus
    menu_elements.main_openDoors_enabled:render("Open Chests", "Enable or disable the chest plugin")

    menu_elements.main_tree:pop()
end

-- Retorna os elementos do menu
return menu_elements