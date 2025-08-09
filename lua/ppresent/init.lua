local M = {}

local function create_floating_window(config, enter)
    if enter == nil then
        enter = false  -- Default to entering the window
    end
    -- Create a buffer
    -- false for no scratch buffer, true for no file
    local buf = vim.api.nvim_create_buf(false, true)

    -- Create the floating window
    local win = vim.api.nvim_open_win(buf, enter, config)

    return { buf = buf, win = win }
end

function M.setup(config)
    config = config or {}
end

--- @class ppresent.Slide
--- @field title string The title of the slide
--- @field body string[] The body of the slide
--- @class ppresent.Slides

--- @class ppresent.Slides
--- @field slides ppresent.Slide[] The slides of the file

--- Takes some lines and parse them into slides
--- @param lines string[] The lines in the buffer
--- @return ppresent.Slides
local function parse_slides(lines)
    local slides = { slides = {} }
    local current_slide = {
        title = "",
        body = {},
    }
    local separator = "^#"
    for _, line in ipairs(lines) do
        if line:find(separator) then
            if #current_slide.title > 0 then
                table.insert(slides.slides, current_slide)
            end
            current_slide = {
                title = line,
                body = {},
            }
        else
            table.insert(current_slide.body, line)
            current_slide = {
                title = current_slide.title,
                body = current_slide.body,
            }
        end
    end
    table.insert(slides.slides, current_slide)
    return slides
end

--- Creates the window configurations for the presentation
--- @return table configurations Table containing:
---   - background vim.api.keyset.win_config: Background window config.
---   - header vim.api.keyset.win_config: Header window config.
---   - body vim.api.keyset.win_config: Body window config.
local function create_window_configurations()
    local width = vim.o.columns
    local height = vim.o.lines

    local header_height = 1 + 2  -- 1 + border
    local footer_height = 1  -- 1, no border
    local body_height = height - header_height - footer_height - 2 - 1 -- for our own border

    return {
        background = {
            relative = "editor",
            width = width,
            height = height,
            style = "minimal",
            col = 1,
            row = 0,
            zindex = 1,
        },
        header = {
            relative = "editor",
            width = width,
            height = 1,
            style = "minimal",
            border = "rounded",
            col = 1,
            row = 0,
            zindex = 2,
        },
        body = {
            relative = "editor",
            width = width - 8,
            height = body_height,
            style = "minimal",
            col = 8,
            row = 4,
            border = { " ", " ", " ", " ", " ", " ", " ", " ", },
        },
        footer = {
            relative = "editor",
            width = width,
            height = 1,
            style = "minimal",
            -- TODO: Just a border on the top?
            -- border = "rounded",
            col = 1,
            row = height - 1,
            zindex = 2,
        }
    }
end

local state = {
    parsed = {},
    current_slide = 1,
    floats = {},
}

local present_keymap = function(mode, key, callback)
    vim.keymap.set(mode, key, callback, {
        buffer = state.floats.body.buf,
    })
end

local foreach_float = function(cb)
    for name, float in pairs(state.floats) do
        cb(name, float)
    end
end

M.start_presentation = function(opts)
    opts = opts or {}
    opts.bufnr = opts.bufnr or 0
    local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
    state.parsed = parse_slides(lines)
    state.current_slide = 1

    local windows = create_window_configurations()

    state.floats.background = create_floating_window(windows.background, false)
    state.floats.header = create_floating_window(windows.header, false)
    state.floats.body = create_floating_window(windows.body, true)
    state.floats.footer = create_floating_window(windows.footer, false)

    foreach_float(function(_, float)
        vim.bo[float.buf].filetype = "markdown"
    end)

    vim.bo[state.floats.header.buf].filetype = "markdown"
    vim.bo[state.floats.body.buf].filetype = "markdown"

    local function set_slide_content(idx)
        local width = vim.o.columns
        local slide = state.parsed.slides[idx]
        local padding = string.rep(" ", (width - #slide.title) / 2)
        local title = padding .. slide.title
        vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, { title })
        vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.body)
        local footer = string.format(
            " %d / %d | %s",
            state.current_slide,
            #state.parsed.slides,
            "TITLE OF CURRENT FILE"
        )
        vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { footer })
    end

    present_keymap("n", "n", function ()
        state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
        set_slide_content(state.current_slide)
    end)

    present_keymap("n", "p", function ()
        state.current_slide = math.max(state.current_slide - 1, 1)
        set_slide_content(state.current_slide)
    end)

    present_keymap("n", "q", function ()
        vim.api.nvim_win_close(state.floats.body.win, true)
    end)

    local restore = {
        cmdheight = {
            original = vim.o.cmdheight,
            present = 0,
        },
    }

    -- Set options for the floating window in presentation mode
    for option, config in pairs(restore) do
        vim.o[option] = config.present
    end

    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = state.floats.body.buf,
        callback = function()
            -- Restore original options when leaving the floating window
            for option, config in pairs(restore) do
                vim.o[option] = config.original
            end

            foreach_float(function(_, float)
                pcall(vim.api.nvim_win_close, float.win, true)
            end)
        end,
    })

    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("ppresent-resized", {}),
        callback = function()
            if not vim.api.nvim_win_is_valid(state.floats.body.win) or state.floats.body_float.win == nil then
                return
            end
            local updated = create_window_configurations()
            foreach_float(function(name, float)
                vim.api.nvim_win_set_config(float.win, updated[name])
            end)
            set_slide_content(state.current_slide)
        end,
    })

    set_slide_content(state.current_slide)
end


M.start_presentation({bufnr = 22})

return M
