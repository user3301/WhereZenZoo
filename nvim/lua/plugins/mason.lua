-- Windows uses Mason for language servers, including Roslyn's supplemental registry.
return {
  "mason-org/mason.nvim",
  opts = {
    ensure_installed = { "roslyn" },
    registries = {
      "github:mason-org/mason-registry",
      "github:Crashdummyy/mason-registry",
    },
  },
}
