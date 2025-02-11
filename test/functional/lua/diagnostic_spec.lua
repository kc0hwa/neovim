local helpers = require('test.functional.helpers')(after_each)

local command = helpers.command
local clear = helpers.clear
local exec_lua = helpers.exec_lua
local eq = helpers.eq
local nvim = helpers.nvim

describe('vim.diagnostic', function()
  before_each(function()
    clear()

    exec_lua [[
      require('vim.diagnostic')

      function make_error(msg, x1, y1, x2, y2)
        return {
          lnum = x1,
          col = y1,
          end_lnum = x2,
          end_col = y2,
          message = msg,
          severity = vim.diagnostic.severity.ERROR,
        }
      end

      function make_warning(msg, x1, y1, x2, y2)
        return {
          lnum = x1,
          col = y1,
          end_lnum = x2,
          end_col = y2,
          message = msg,
          severity = vim.diagnostic.severity.WARN,
        }
      end

      function make_information(msg, x1, y1, x2, y2)
        return {
          lnum = x1,
          col = y1,
          end_lnum = x2,
          end_col = y2,
          message = msg,
          severity = vim.diagnostic.severity.INFO,
        }
      end

      function make_hint(msg, x1, y1, x2, y2)
        return {
          lnum = x1,
          col = y1,
          end_lnum = x2,
          end_col = y2,
          message = msg,
          severity = vim.diagnostic.severity.HINT,
        }
      end

      function count_diagnostics(bufnr, severity, namespace)
        return #vim.diagnostic.get(bufnr, {severity = severity, namespace = namespace})
      end

      function count_extmarks(bufnr, namespace)
        return #vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
      end
    ]]

    exec_lua([[
      diagnostic_ns = vim.api.nvim_create_namespace("diagnostic_spec")
      other_ns = vim.api.nvim_create_namespace("other_namespace")
      diagnostic_bufnr = vim.api.nvim_create_buf(true, false)
      local lines = {"1st line of text", "2nd line of text", "wow", "cool", "more", "lines"}
      vim.fn.bufload(diagnostic_bufnr)
      vim.api.nvim_buf_set_lines(diagnostic_bufnr, 0, 1, false, lines)
      return diagnostic_bufnr
    ]])
  end)

  after_each(function()
    clear()
  end)

  it('creates highlight groups', function()
    command('runtime plugin/diagnostic.vim')
    eq({
      'DiagnosticError',
      'DiagnosticFloatingError',
      'DiagnosticFloatingHint',
      'DiagnosticFloatingInfo',
      'DiagnosticFloatingWarn',
      'DiagnosticHint',
      'DiagnosticInfo',
      'DiagnosticSignError',
      'DiagnosticSignHint',
      'DiagnosticSignInfo',
      'DiagnosticSignWarn',
      'DiagnosticUnderlineError',
      'DiagnosticUnderlineHint',
      'DiagnosticUnderlineInfo',
      'DiagnosticUnderlineWarn',
      'DiagnosticVirtualTextError',
      'DiagnosticVirtualTextHint',
      'DiagnosticVirtualTextInfo',
      'DiagnosticVirtualTextWarn',
      'DiagnosticWarn',
    }, exec_lua([[return vim.fn.getcompletion('Diagnostic', 'highlight')]]))
  end)

  it('retrieves diagnostics from all buffers and namespaces', function()
    local result = exec_lua [[
      vim.diagnostic.set(diagnostic_ns, 1, {
        make_error('Diagnostic #1', 1, 1, 1, 1),
        make_error('Diagnostic #2', 2, 1, 2, 1),
      })
      vim.diagnostic.set(other_ns, 2, {
        make_error('Diagnostic #3', 3, 1, 3, 1),
      })
      return vim.diagnostic.get()
    ]]
    eq(3, #result)
    eq(2, exec_lua([[return #vim.tbl_filter(function(d) return d.bufnr == 1 end, ...)]], result))
    eq('Diagnostic #1', result[1].message)
  end)

  it('saves and count a single error', function()
    eq(1, exec_lua [[
      vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
        make_error('Diagnostic #1', 1, 1, 1, 1),
      })
      return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)
    ]])
  end)

  it('saves and count multiple errors', function()
    eq(2, exec_lua [[
      vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
        make_error('Diagnostic #1', 1, 1, 1, 1),
        make_error('Diagnostic #2', 2, 1, 2, 1),
      })
      return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)
    ]])
  end)

  it('saves and count from multiple namespaces', function()
    eq({1, 1, 2}, exec_lua [[
      vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
        make_error('Diagnostic From Server 1', 1, 1, 1, 1),
      })
      vim.diagnostic.set(other_ns, diagnostic_bufnr, {
        make_error('Diagnostic From Server 2', 1, 1, 1, 1),
      })
      return {
        -- First namespace
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
        -- Second namespace
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, other_ns),
        -- All namespaces
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR),
      }
    ]])
  end)

  it('saves and count from multiple namespaces with respect to severity', function()
    eq({3, 0, 3}, exec_lua [[
      vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
        make_error('Diagnostic From Server 1:1', 1, 1, 1, 1),
        make_error('Diagnostic From Server 1:2', 2, 2, 2, 2),
        make_error('Diagnostic From Server 1:3', 2, 3, 3, 2),
      })
      vim.diagnostic.set(other_ns, diagnostic_bufnr, {
        make_warning('Warning From Server 2', 3, 3, 3, 3),
      })
      return {
        -- Namespace 1
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
        -- Namespace 2
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, other_ns),
        -- All namespaces
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR),
      }
    ]])
  end)

  it('handles one namespace clearing highlights while the other still has highlights', function()
    -- 1 Error (1)
    -- 1 Warning (2)
    -- 1 Warning (2) + 1 Warning (1)
    -- 2 highlights and 2 underlines (since error)
    -- 1 highlight + 1 underline
    local all_highlights = {1, 1, 2, 4, 2}
    eq(all_highlights, exec_lua [[
      local ns_1_diags = {
        make_error("Error 1", 1, 1, 1, 5),
        make_warning("Warning on Server 1", 2, 1, 2, 5),
      }
      local ns_2_diags = {
        make_warning("Warning 1", 2, 1, 2, 5),
      }

      vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, ns_1_diags)
      vim.diagnostic.set(other_ns, diagnostic_bufnr, ns_2_diags)

      return {
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN, other_ns),
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN),
        count_extmarks(diagnostic_bufnr, diagnostic_ns),
        count_extmarks(diagnostic_bufnr, other_ns),
      }
    ]])

    -- Clear diagnostics from namespace 1, and make sure we have the right amount of stuff for namespace 2
    eq({1, 1, 2, 0, 2}, exec_lua [[
      vim.diagnostic.disable(diagnostic_bufnr, diagnostic_ns)
      return {
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN, other_ns),
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN),
        count_extmarks(diagnostic_bufnr, diagnostic_ns),
        count_extmarks(diagnostic_bufnr, other_ns),
      }
    ]])

    -- Show diagnostics from namespace 1 again
    eq(all_highlights, exec_lua([[
      vim.diagnostic.enable(diagnostic_bufnr, diagnostic_ns)
      return {
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN, other_ns),
        count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN),
        count_extmarks(diagnostic_bufnr, diagnostic_ns),
        count_extmarks(diagnostic_bufnr, other_ns),
      }
    ]]))
  end)

  it('does not display diagnostics when disabled', function()
    eq({0, 2}, exec_lua [[
      local ns_1_diags = {
        make_error("Error 1", 1, 1, 1, 5),
        make_warning("Warning on Server 1", 2, 1, 2, 5),
      }
      local ns_2_diags = {
        make_warning("Warning 1", 2, 1, 2, 5),
      }

      vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, ns_1_diags)
      vim.diagnostic.set(other_ns, diagnostic_bufnr, ns_2_diags)

      vim.diagnostic.disable(diagnostic_bufnr, diagnostic_ns)

      return {
        count_extmarks(diagnostic_bufnr, diagnostic_ns),
        count_extmarks(diagnostic_bufnr, other_ns),
      }
    ]])

    eq({4, 0}, exec_lua [[
      vim.diagnostic.enable(diagnostic_bufnr, diagnostic_ns)
      vim.diagnostic.disable(diagnostic_bufnr, other_ns)

      return {
        count_extmarks(diagnostic_bufnr, diagnostic_ns),
        count_extmarks(diagnostic_bufnr, other_ns),
      }
    ]])
  end)

  describe('reset()', function()
    it('diagnostic count is 0 and displayed diagnostics are 0 after call', function()
      -- 1 Error (1)
      -- 1 Warning (2)
      -- 1 Warning (2) + 1 Warning (1)
      -- 2 highlights and 2 underlines (since error)
      -- 1 highlight + 1 underline
      local all_highlights = {1, 1, 2, 4, 2}
      eq(all_highlights, exec_lua [[
        local ns_1_diags = {
          make_error("Error 1", 1, 1, 1, 5),
          make_warning("Warning on Server 1", 2, 1, 2, 5),
        }
        local ns_2_diags = {
          make_warning("Warning 1", 2, 1, 2, 5),
        }

        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, ns_1_diags)
        vim.diagnostic.set(other_ns, diagnostic_bufnr, ns_2_diags)

        return {
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN, other_ns),
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN),
          count_extmarks(diagnostic_bufnr, diagnostic_ns),
          count_extmarks(diagnostic_bufnr, other_ns),
        }
      ]])

      -- Reset diagnostics from namespace 1
      exec_lua([[ vim.diagnostic.reset(diagnostic_ns) ]])

      -- Make sure we have the right diagnostic count
      eq({0, 1, 1, 0, 2} , exec_lua [[
        local diagnostic_count = {}
        vim.wait(100, function () diagnostic_count = {
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN, other_ns),
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN),
          count_extmarks(diagnostic_bufnr, diagnostic_ns),
          count_extmarks(diagnostic_bufnr, other_ns),
        } end )
        return diagnostic_count
      ]])

      -- Reset diagnostics from namespace 2
      exec_lua([[ vim.diagnostic.reset(other_ns) ]])

      -- Make sure we have the right diagnostic count
      eq({0, 0, 0, 0, 0}, exec_lua [[
        local diagnostic_count = {}
        vim.wait(100, function () diagnostic_count = {
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns),
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN, other_ns),
          count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.WARN),
          count_extmarks(diagnostic_bufnr, diagnostic_ns),
          count_extmarks(diagnostic_bufnr, other_ns),
        } end )
        return diagnostic_count
      ]])

    end)
  end)

  describe('get_next_pos()', function()
    it('can find the next pos with only one namespace', function()
      eq({1, 1}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #1', 1, 1, 1, 1),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        return vim.diagnostic.get_next_pos()
      ]])
    end)

    it('can find next pos with two errors', function()
      eq({4, 4}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #1', 1, 1, 1, 1),
          make_error('Diagnostic #2', 4, 4, 4, 4),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {3, 1})
        return vim.diagnostic.get_next_pos { namespace = diagnostic_ns }
      ]])
    end)

    it('can cycle when position is past error', function()
      eq({1, 1}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #1', 1, 1, 1, 1),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {3, 1})
        return vim.diagnostic.get_next_pos { namespace = diagnostic_ns }
      ]])
    end)

    it('will not cycle when wrap is off', function()
      eq(false, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #1', 1, 1, 1, 1),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {3, 1})
        return vim.diagnostic.get_next_pos { namespace = diagnostic_ns, wrap = false }
      ]])
    end)

    it('can cycle even from the last line', function()
      eq({4, 4}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #2', 4, 4, 4, 4),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {vim.api.nvim_buf_line_count(0), 1})
        return vim.diagnostic.get_prev_pos { namespace = diagnostic_ns }
      ]])
    end)
  end)

  describe('get_prev_pos()', function()
    it('can find the prev pos with only one namespace', function()
      eq({1, 1}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #1', 1, 1, 1, 1),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {3, 1})
        return vim.diagnostic.get_prev_pos()
      ]])
    end)

    it('can find prev pos with two errors', function()
      eq({1, 1}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #1', 1, 1, 1, 1),
          make_error('Diagnostic #2', 4, 4, 4, 4),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {3, 1})
        return vim.diagnostic.get_prev_pos { namespace = diagnostic_ns }
      ]])
    end)

    it('can cycle when position is past error', function()
      eq({4, 4}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #2', 4, 4, 4, 4),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {3, 1})
        return vim.diagnostic.get_prev_pos { namespace = diagnostic_ns }
      ]])
    end)

    it('respects wrap parameter', function()
      eq(false, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic #2', 4, 4, 4, 4),
        })
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.api.nvim_win_set_cursor(0, {3, 1})
        return vim.diagnostic.get_prev_pos { namespace = diagnostic_ns, wrap = false}
      ]])
    end)
  end)

  describe('get()', function()
    it('returns an empty table when no diagnostics are present', function()
      eq({}, exec_lua [[return vim.diagnostic.get(diagnostic_bufnr, {namespace=diagnostic_ns})]])
    end)

    it('returns all diagnostics when no severity is supplied', function()
      eq(2, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error("Error 1", 1, 1, 1, 5),
          make_warning("Warning on Server 1", 1, 1, 2, 5),
        })

        return #vim.diagnostic.get(diagnostic_bufnr)
      ]])
    end)

    it('returns only requested diagnostics when severity is supplied', function()
      eq({2, 3, 2}, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error("Error 1", 1, 1, 1, 5),
          make_warning("Warning on Server 1", 1, 1, 2, 5),
          make_information("Ignored information", 1, 1, 2, 5),
          make_hint("Here's a hint", 1, 1, 2, 5),
        })

        return {
          #vim.diagnostic.get(diagnostic_bufnr, { severity = {min=vim.diagnostic.severity.WARN} }),
          #vim.diagnostic.get(diagnostic_bufnr, { severity = {max=vim.diagnostic.severity.WARN} }),
          #vim.diagnostic.get(diagnostic_bufnr, {
            severity = {
              min=vim.diagnostic.severity.INFO,
              max=vim.diagnostic.severity.WARN,
            }
          }),
        }
      ]])
    end)

    it('allows filtering by line', function()
      eq(1, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error("Error 1", 1, 1, 1, 5),
          make_warning("Warning on Server 1", 1, 1, 2, 5),
          make_information("Ignored information", 1, 1, 2, 5),
          make_error("Error On Other Line", 2, 1, 1, 5),
        })

        return #vim.diagnostic.get(diagnostic_bufnr, {lnum = 2})
      ]])
    end)
  end)

  describe('config()', function()
    it('can use functions for config values', function()
      exec_lua [[
        vim.diagnostic.config({
          virtual_text = function() return true end,
        }, diagnostic_ns)
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Delayed Diagnostic', 4, 4, 4, 4),
        })
      ]]

      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(2, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])

      -- Now, don't enable virtual text.
      -- We should have one less extmark displayed.
      exec_lua [[
        vim.diagnostic.config({
          virtual_text = function() return false end,
        }, diagnostic_ns)
      ]]

      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(1, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])
    end)

    it('allows filtering by severity', function()
      local get_extmark_count_with_severity = function(min_severity)
        return exec_lua([[
          vim.diagnostic.config({
            underline = false,
            virtual_text = {
              severity = {min=...},
            },
          })

          vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
            make_warning('Delayed Diagnostic', 4, 4, 4, 4),
          })

          return count_extmarks(diagnostic_bufnr, diagnostic_ns)
        ]], min_severity)
      end

      -- No messages with Error or higher
      eq(0, get_extmark_count_with_severity("ERROR"))

      -- But now we don't filter it
      eq(1, get_extmark_count_with_severity("WARN"))
      eq(1, get_extmark_count_with_severity("HINT"))
    end)
  end)

  describe('set()', function()
    it('can perform updates after insert_leave', function()
      exec_lua [[vim.api.nvim_set_current_buf(diagnostic_bufnr)]]
      nvim("input", "o")
      eq({mode='i', blocking=false}, nvim("get_mode"))

      -- Save the diagnostics
      exec_lua [[
        vim.diagnostic.config({
          update_in_insert = false,
        })
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Delayed Diagnostic', 4, 4, 4, 4),
        })
      ]]

      -- No diagnostics displayed yet.
      eq({mode='i', blocking=false}, nvim("get_mode"))
      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(0, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])

      nvim("input", "<esc>")
      eq({mode='n', blocking=false}, nvim("get_mode"))

      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(2, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])
    end)

    it('does not perform updates when not needed', function()
      exec_lua [[vim.api.nvim_set_current_buf(diagnostic_bufnr)]]
      nvim("input", "o")
      eq({mode='i', blocking=false}, nvim("get_mode"))

      -- Save the diagnostics
      exec_lua [[
        vim.diagnostic.config({
          update_in_insert = false,
          virtual_text = true,
        })

        -- Count how many times we call display.
        SetVirtualTextOriginal = vim.diagnostic._set_virtual_text

        DisplayCount = 0
        vim.diagnostic._set_virtual_text = function(...)
          DisplayCount = DisplayCount + 1
          return SetVirtualTextOriginal(...)
        end

        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Delayed Diagnostic', 4, 4, 4, 4),
        })
      ]]

      -- No diagnostics displayed yet.
      eq({mode='i', blocking=false}, nvim("get_mode"))
      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(0, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])
      eq(0, exec_lua [[return DisplayCount]])

      nvim("input", "<esc>")
      eq({mode='n', blocking=false}, nvim("get_mode"))

      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(2, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])
      eq(1, exec_lua [[return DisplayCount]])

      -- Go in and out of insert mode one more time.
      nvim("input", "o")
      eq({mode='i', blocking=false}, nvim("get_mode"))

      nvim("input", "<esc>")
      eq({mode='n', blocking=false}, nvim("get_mode"))

      -- Should not have set the virtual text again.
      eq(1, exec_lua [[return DisplayCount]])
    end)

    it('never sets virtual text, in combination with insert leave', function()
      exec_lua [[vim.api.nvim_set_current_buf(diagnostic_bufnr)]]
      nvim("input", "o")
      eq({mode='i', blocking=false}, nvim("get_mode"))

      -- Save the diagnostics
      exec_lua [[
        vim.diagnostic.config({
          update_in_insert = false,
          virtual_text = false,
        })

        -- Count how many times we call display.
        SetVirtualTextOriginal = vim.diagnostic._set_virtual_text

        DisplayCount = 0
        vim.diagnostic._set_virtual_text = function(...)
          DisplayCount = DisplayCount + 1
          return SetVirtualTextOriginal(...)
        end

        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Delayed Diagnostic', 4, 4, 4, 4),
        })
      ]]

      -- No diagnostics displayed yet.
      eq({mode='i', blocking=false}, nvim("get_mode"))
      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(0, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])
      eq(0, exec_lua [[return DisplayCount]])

      nvim("input", "<esc>")
      eq({mode='n', blocking=false}, nvim("get_mode"))

      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(1, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])
      eq(0, exec_lua [[return DisplayCount]])

      -- Go in and out of insert mode one more time.
      nvim("input", "o")
      eq({mode='i', blocking=false}, nvim("get_mode"))

      nvim("input", "<esc>")
      eq({mode='n', blocking=false}, nvim("get_mode"))

      -- Should not have set the virtual text still.
      eq(0, exec_lua [[return DisplayCount]])
    end)

    it('can perform updates while in insert mode, if desired', function()
      exec_lua [[vim.api.nvim_set_current_buf(diagnostic_bufnr)]]
      nvim("input", "o")
      eq({mode='i', blocking=false}, nvim("get_mode"))

      -- Save the diagnostics
      exec_lua [[
        vim.diagnostic.config({
          update_in_insert = true,
        })

        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Delayed Diagnostic', 4, 4, 4, 4),
        })
      ]]

      -- Diagnostics are displayed, because the user wanted them that way!
      eq({mode='i', blocking=false}, nvim("get_mode"))
      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(2, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])

      nvim("input", "<esc>")
      eq({mode='n', blocking=false}, nvim("get_mode"))

      eq(1, exec_lua [[return count_diagnostics(diagnostic_bufnr, vim.diagnostic.severity.ERROR, diagnostic_ns)]])
      eq(2, exec_lua [[return count_extmarks(diagnostic_bufnr, diagnostic_ns)]])
    end)

    it('can set diagnostics without displaying them', function()
      eq(0, exec_lua [[
        vim.diagnostic.disable(diagnostic_bufnr, diagnostic_ns)
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic From Server 1:1', 1, 1, 1, 1),
        })
        return count_extmarks(diagnostic_bufnr, diagnostic_ns)
      ]])

      eq(2, exec_lua [[
        vim.diagnostic.enable(diagnostic_bufnr, diagnostic_ns)
        return count_extmarks(diagnostic_bufnr, diagnostic_ns)
      ]])
    end)

    it('can set display options', function()
      eq(0, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic From Server 1:1', 1, 1, 1, 1),
        }, { virtual_text = false, underline = false })
        return count_extmarks(diagnostic_bufnr, diagnostic_ns)
      ]])

      eq(1, exec_lua [[
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Diagnostic From Server 1:1', 1, 1, 1, 1),
        }, { virtual_text = true, underline = false })
        return count_extmarks(diagnostic_bufnr, diagnostic_ns)
      ]])
    end)
  end)

  describe('show_line_diagnostics()', function()
    it('creates floating window and returns popup bufnr and winnr if current line contains diagnostics', function()
      -- Two lines:
      --    Diagnostic:
      --    1. <msg>
      eq(2, exec_lua [[
        local diagnostics = {
          make_error("Syntax error", 0, 1, 0, 3),
        }
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, diagnostics)
        local popup_bufnr, winnr = vim.diagnostic.show_line_diagnostics()
        return #vim.api.nvim_buf_get_lines(popup_bufnr, 0, -1, false)
      ]])
    end)

    it('creates floating window and returns popup bufnr and winnr without header, if requested', function()
      -- One line (since no header):
      --    1. <msg>
      eq(1, exec_lua [[
        local diagnostics = {
          make_error("Syntax error", 0, 1, 0, 3),
        }
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, diagnostics)
        local popup_bufnr, winnr = vim.diagnostic.show_line_diagnostics {show_header = false}
        return #vim.api.nvim_buf_get_lines(popup_bufnr, 0, -1, false)
      ]])
    end)
  end)

  describe('set_signs()', function()
    -- TODO(tjdevries): Find out why signs are not displayed when set from Lua...??
    pending('sets signs by default', function()
      exec_lua [[
        vim.diagnostic.config({
          update_in_insert = true,
          signs = true,
        })

        local diagnostics = {
          make_error('Delayed Diagnostic', 1, 1, 1, 2),
          make_error('Delayed Diagnostic', 3, 3, 3, 3),
        }

        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)
        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, diagnostics)

        vim.diagnostic._set_signs(diagnostic_ns, diagnostic_bufnr, diagnostics)
        -- return vim.fn.sign_getplaced()
      ]]

      nvim("input", "o")
      nvim("input", "<esc>")

      -- TODO(tjdevries): Find a way to get the signs to display in the test...
      eq(nil, exec_lua [[
        return im.fn.sign_getplaced()[1].signs
      ]])
    end)
  end)

  describe('setloclist()', function()
    it('sets diagnostics in lnum order', function()
      local loc_list = exec_lua [[
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)

        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Farther Diagnostic', 4, 4, 4, 4),
          make_error('Lower Diagnostic', 1, 1, 1, 1),
        })

        vim.diagnostic.setloclist()

        return vim.fn.getloclist(0)
      ]]

      assert(loc_list[1].lnum < loc_list[2].lnum)
    end)

    it('sets diagnostics in lnum order, regardless of namespace', function()
      local loc_list = exec_lua [[
        vim.api.nvim_win_set_buf(0, diagnostic_bufnr)

        vim.diagnostic.set(diagnostic_ns, diagnostic_bufnr, {
          make_error('Lower Diagnostic', 1, 1, 1, 1),
        })

        vim.diagnostic.set(other_ns, diagnostic_bufnr, {
          make_warning('Farther Diagnostic', 4, 4, 4, 4),
        })

        vim.diagnostic.setloclist()

        return vim.fn.getloclist(0)
      ]]

      assert(loc_list[1].lnum < loc_list[2].lnum)
    end)
  end)
end)
