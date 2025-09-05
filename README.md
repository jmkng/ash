# Roadmap

This is going to be a general purpose text templating engine, something like Jinja in Python or Tera in Rust.

The parser will be written by hand so it should be nice and fast, and provide some really helpful error messages when you mess the syntax up.

I'd like the syntax to be Zig-like so your muscle memory isn't punished for writing a for loop like this:

```
for (items) |item| ...
```

But at the same time, it's fine to just drop the extra symbols, since this is just a dynamic template language and doesn't need to be so strict:

```
for items item ...
// Or..
for items item, index ...
```

That being said, I don't really care to compile down to Zig functions or anything like that.

## Features

- [ ] Basic statements (if/for)
- [ ] Variable declarations (var/const)
- [ ] Multiple strategies for template inheritance
  - [ ] Partial includes
  - [ ] Extend parent
- [x] Custom delimiters
- [ ] User-defined filters for transforming content.
    - [ ] A standard library for common functionality, like escaping HTML.

## Phase 1

Develop a lexer that can produce a stream of tokens.

- [ ] Lexer
  - [x] Find a way to quickly scan text for patterns

>Scanning was extracted to a separate library, [Scout](https://github.com/jmkng/scout).

## Phase 2

Develop a parser than can build an AST from the tokens produced by a lexer.

- [ ] Parser

## Phase 3

Develop a renderer that can read the AST built by a parser, and generate output.

- [ ] Renderer
