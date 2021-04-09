using Pkg

Pkg.activate(".")
Pkg.instantiate()

push!(LOAD_PATH,"../src/")

using Documenter, DocumenterMarkdown, FastRunningMedian

makedocs(
    format=Markdown(),
    modules=[FastRunningMedian]
    )

cp("build/README.md", "../README.md", force=true)