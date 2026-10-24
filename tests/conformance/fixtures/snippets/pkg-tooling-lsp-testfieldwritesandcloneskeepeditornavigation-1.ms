# conform: tags=closures,diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/mutation_test.go:11 TestFieldWritesAndClonesKeepEditorNavigation
type Val:
    val: Int

def work(var value: Val) -> Unit:
    let callback = lambda () -> Unit:
        value.val = value.val + 1
    callback()

    let copy = value.clone()
    let list = [copy]
    list.clone().append(value)
