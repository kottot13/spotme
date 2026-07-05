-- Localization. Base language is enUS (fallback for any client locale),
-- plus full translations. The language is chosen by GetLocale() automatically.
-- To add a language: copy the block below and override the needed keys.

local _, ns = ...

-- ===== enUS (base / fallback) =====
local L = {
    -- panel
    WHERE        = "Where to show",
    WORLD_CB     = "Glow on the world map",
    WORLD_TIP    = "The big map (M key)",
    MINI_CB      = "Glow on the minimap",
    MINI_TIP     = "Around the center arrow",
    LOOK         = "Appearance",
    THEME_LBL    = "Theme",
    THEME_TIP    = "Textures, color and animation style",
    COLOR_LBL    = "Color",
    COLOR_TIP    = "Glow color",
    COL_THEME    = "By theme",
    COL_RAINBOW  = "Rainbow",
    COL_CLASS    = "Class color",
    FLICKER_CB   = "Brightness flicker",
    FLICKER_TIP  = "Soft brightness breathing",
    SIZES        = "Sizes",
    ARROW_SL     = "Arrow size (map)",
    ARROW_TIP    = "Default is 27",
    GLOW_SL      = "Glow size (map)",
    MINI_SL      = "Glow size (minimap)",
    SPEED_SL     = "Rainbow speed",
    -- theme names
    T_arcane     = "Arcane",
    T_fire       = "Fire",
    T_lightning  = "Lightning",
    T_ice        = "Ice",
    T_holy       = "Holy",
    T_shadow     = "Shadow",
    -- slash
    PANEL_NA     = "Panel unavailable — use commands (/sm help)",
    HELP_SCREENS = "screens: world | minimap | on | off",
    HELP_THEMES  = "themes: theme %s",
    HELP_COLORS  = "colors: %s | rainbow | class | color r g b",
    HELP_MISC    = "other: flicker | speed N | arrow N | glowsize N | minisize N | status | reset",
    ON           = "on",
    OFF          = "off",
    WORLD_STATE  = "world map: %s",
    MINI_STATE   = "minimap: %s",
    ALL_ON       = "enabled everywhere",
    ALL_OFF      = "disabled everywhere",
    THEME_SET    = "theme: %s",
    THEMES_LIST  = "themes: %s",
    FLICKER_STATE= "flicker: %s",
    MODE_RAINBOW = "mode: rainbow",
    MODE_CLASS   = "mode: class color",
    SPEED_SET    = "rainbow speed: %s",
    SPEED_FMT    = "format: /sm speed 0.1",
    ARROW_SET    = "arrow size: %s",
    ARROW_FMT    = "format: /sm arrow 40 (default 27)",
    GLOW_SET     = "glow (map): %s",
    GLOW_FMT     = "format: /sm glowsize 85",
    MSIZE_SET    = "glow (minimap): %s",
    MSIZE_FMT    = "format: /sm minisize 46",
    COLOR_SET    = "color: %s",
    COLOR_DONE   = "color set",
    COLOR_FMT    = "format: /sm color 1.0 0.3 0.95",
    UNKNOWN      = "unknown. /sm help — commands, /sm — settings panel",
    -- party locator
    PL_TITLE        = "Party",
    PL_OUTOFAREA    = "out of area",
    PL_COPY         = "Copy",
    PL_NOPARTY      = "You are not in a party",
    PL_BTN_TIP      = "Click: party locator",
    PL_BUTTON_STATE = "minimap button: %s",
    HELP_PARTY      = "party: party (open list) | button (minimap button)",
}

-- ===== ruRU =====
if GetLocale() == "ruRU" then
    L.WHERE        = "Где показывать"
    L.WORLD_CB     = "Свечение на большой карте"
    L.WORLD_TIP    = "Кнопка M"
    L.MINI_CB      = "Свечение на миникарте"
    L.MINI_TIP     = "Вокруг центральной стрелки"
    L.LOOK         = "Вид"
    L.THEME_LBL    = "Тема"
    L.THEME_TIP    = "Текстуры, цвет и характер анимации"
    L.COLOR_LBL    = "Цвет"
    L.COLOR_TIP    = "Цвет свечения"
    L.COL_THEME    = "По теме"
    L.COL_RAINBOW  = "Радуга"
    L.COL_CLASS    = "Цвет класса"
    L.FLICKER_CB   = "Мерцание яркости"
    L.FLICKER_TIP  = "Мягкое «дыхание» яркости"
    L.SIZES        = "Размеры"
    L.ARROW_SL     = "Размер стрелки (карта)"
    L.ARROW_TIP    = "Штатный 27"
    L.GLOW_SL      = "Размер свечения (карта)"
    L.MINI_SL      = "Размер свечения (мини)"
    L.SPEED_SL     = "Скорость радуги"
    L.T_arcane     = "Магия"
    L.T_fire       = "Огонь"
    L.T_lightning  = "Молния"
    L.T_ice        = "Лёд"
    L.T_holy       = "Свет"
    L.T_shadow     = "Тень"
    L.PANEL_NA     = "панель недоступна — используй команды (/sm help)"
    L.HELP_SCREENS = "экраны: world | minimap | on | off"
    L.HELP_THEMES  = "темы: theme %s"
    L.HELP_COLORS  = "цвет: %s | rainbow | class | color r g b"
    L.HELP_MISC    = "прочее: flicker | speed N | arrow N | glowsize N | minisize N | status | reset"
    L.ON           = "вкл"
    L.OFF          = "выкл"
    L.WORLD_STATE  = "большая карта: %s"
    L.MINI_STATE   = "миникарта: %s"
    L.ALL_ON       = "включено везде"
    L.ALL_OFF      = "выключено везде"
    L.THEME_SET    = "тема: %s"
    L.THEMES_LIST  = "темы: %s"
    L.FLICKER_STATE= "мерцание: %s"
    L.MODE_RAINBOW = "режим: радуга"
    L.MODE_CLASS   = "режим: цвет класса"
    L.SPEED_SET    = "скорость радуги: %s"
    L.SPEED_FMT    = "формат: /sm speed 0.1"
    L.ARROW_SET    = "размер стрелки: %s"
    L.ARROW_FMT    = "формат: /sm arrow 40 (штатный 27)"
    L.GLOW_SET     = "свечение (карта): %s"
    L.GLOW_FMT     = "формат: /sm glowsize 85"
    L.MSIZE_SET    = "свечение (мини): %s"
    L.MSIZE_FMT    = "формат: /sm minisize 46"
    L.COLOR_SET    = "цвет: %s"
    L.COLOR_DONE   = "цвет задан"
    L.COLOR_FMT    = "формат: /sm color 1.0 0.3 0.95"
    L.UNKNOWN      = "неизвестно. /sm help — команды, /sm — панель настроек"
    L.PL_TITLE        = "Пати"
    L.PL_OUTOFAREA    = "вне зоны"
    L.PL_COPY         = "Копировать"
    L.PL_NOPARTY      = "Вы не в группе"
    L.PL_BTN_TIP      = "Клик: список пати"
    L.PL_BUTTON_STATE = "кнопка на миникарте: %s"
    L.HELP_PARTY      = "пати: party (список) | button (кнопка на миникарте)"
end

ns.L = L
