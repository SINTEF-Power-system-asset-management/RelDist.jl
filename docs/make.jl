push!(LOAD_PATH, "../src/")
using Documenter, RelDist

makedocs(
    sitename = "RelDist documentation",
    pages = ["Home" => "index.md", "Method explained" => "reldist.md"],
)
deploydocs(repo = "github.com/SINTEF-Power-system-asset-management/RelDist.jl.git")
