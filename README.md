# Eirinchan

This is a remake of the Vichan imageboard software in Elixir and Phoenix. Feature parity is partial; however, this is mostly
contained to removing features I don't personally use. The purpose of this is to replace the PHP/HTML/MySQL type of imageboard with a compiled
high-speed app. Uses PostgreSQL. Credit to Tinyboard, Vichan Devel and Fredrick Brennan.

# Unique Features
- Lightning fast speeds with Phoenix and PostgreSQL
- Modernization to catalog and other page templates
- Catalog pagination, updated catalog search js
- Configurability to new themes such as a faq and flags page
- Configurable multi flags system
- IpAccessConf theme, a security system based on only allowing certain subnets to post + a password page for having your subnet added
- New themes from the bantculture community + Tomorrow
- Live updates using md5 checksum values, including live catalog and index pages
- Large amounts of standard Vichan js migrated downwards into PHP and Elixir
- Embeds can be used alongside files
- 4chanX inspired thread watcher mainly using backend functionality and minimal JS