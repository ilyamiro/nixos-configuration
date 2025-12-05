{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    vimAlias = false;

    plugins = with pkgs.vimPlugins; [
      gruvbox-nvim

      plenary-nvim
      nvim-web-devicons
      
      nvim-tree-lua 

      telescope-nvim

      nvim-lspconfig
      
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      cmp-cmdline
      
      luasnip
      cmp_luasnip

      vim-nix
      vim-polyglot
    ];

    extraConfig = ''
      set termguicolors
      
      colorscheme gruvbox
      hi Normal guibg=none ctermbg=none
      hi NonText guibg=none ctermbg=none

      let mapleader = " "

      nnoremap <silent> <C-n> :NvimTreeToggle<CR>

      nnoremap <leader>ff <cmd>Telescope find_files<CR>
      nnoremap <leader>fg <cmd>Telescope live_grep<CR>
      nnoremap <leader>fb <cmd>Telescope buffers<CR>
    '';

    extraLuaConfig = ''
      require("nvim-tree").setup {}

      require('telescope').setup {}

      local cmp = require'cmp'
      local luasnip = require'luasnip'
      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      vim.lsp.config('pyright', {
        capabilities = capabilities,
      })
      vim.lsp.enable('pyright')

      vim.lsp.config('lua_ls', {
        capabilities = capabilities,
        settings = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
            },
            diagnostics = {
              globals = { 'vim' },
            },
            workspace = {
              maxPreload = 2000,
              checkThirdParty = false,
            },
          },
        },
      })
      vim.lsp.enable('lua_ls')

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'buffer' },
          { name = 'path' },
        }),
      })

      cmp.setup.cmdline('/', {
        sources = cmp.config.sources({
          { name = 'buffer' }
        })
      })

      cmp.setup.cmdline(':', {
        sources = cmp.config.sources({
          { name = 'path' },
          { name = 'cmdline' }
        })
      })
    '';
  };
}

