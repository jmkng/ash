# Roadmap

This is going to be a general purpose text templating engine, something like Jinja in Python or Tera in Rust. I want this library to return helpful error messages and be reasonably fast, so I'll be building the parser by hand, rather than using some kind of library similar to Pest, like Tera does.

## Features

- [ ] Basic in-template logic (if/for)
- [ ] Variable declarations (var/const)
- [ ] Multiple strategies for template inheritance (block+extends, include)
- [ ] Custom delimiters.
- [ ] User-defined filters for transforming content.
    - [ ] A standard library for common functionality, like escaping HTML.

## Phase 1

Develop a lexer that can yield a stream of tokens.

- [ ] Lexer
  - [x] Find a way to quickly scan text for patterns

Pattern scanning was extracted to a separate library, [Scout](https://github.com).

## Phase 2

Develop a parser than can build an AST from the tokens yielded by a lexer.

- [ ] Parser

## Phase 3

Develop a renderer that can read the AST built by a parser, and generate output.

- [ ] Renderer