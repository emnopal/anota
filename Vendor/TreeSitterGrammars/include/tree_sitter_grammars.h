#ifndef TREE_SITTER_GRAMMARS_H
#define TREE_SITTER_GRAMMARS_H
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_json(void);
const TSLanguage *tree_sitter_yaml(void);
const TSLanguage *tree_sitter_toml(void);
const TSLanguage *tree_sitter_ini(void);
const TSLanguage *tree_sitter_python(void);
const TSLanguage *tree_sitter_javascript(void);
const TSLanguage *tree_sitter_typescript(void);
const TSLanguage *tree_sitter_tsx(void);
const TSLanguage *tree_sitter_go(void);
const TSLanguage *tree_sitter_c(void);
const TSLanguage *tree_sitter_cpp(void);
const TSLanguage *tree_sitter_rust(void);
const TSLanguage *tree_sitter_swift(void);
const TSLanguage *tree_sitter_bash(void);
#endif
