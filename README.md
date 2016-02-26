# Carbon-web-framework
An expiremental perl web framework with routing, dynamic files, templating, and a database

## Carbon
Carbon is a simple multi-threaded http server which mounts a router which routes any http requests recieved

The Carbon::Nanotube router is recommended for use with it, however the api is incredibly simple and you can quickly write your own router

## Carbon::Fiber
An efficient generic router which allows text or regex routes to basic file directories, subroutines, or mapping to other routes with optional route arguments

## Carbon::Nanotube
A powerful router extending Carbon::Fiber to allow dynamic files by mounting a compiler which compiles and runs requested files. Also provides pre-compilation, pre-including, and compiled file caching

By default, it uses Carbon::Anthracite as its compiler

## Carbon::Anthracite
A compiler for use with Carbon::Nanotube which compiles dynamic files into a perl subroutine and then executes it in a runtime. Anthracite also contains a plugin api for extending its functionality

## Carbon::Graphite
A versatile templating language for Carbon::Anthracite which can seemlessly be used with regular dynamic files via the Carbon::Anthracite::Plugins::Graphite plugin

## Carbon::Limestone
An effective multi-threaded 64-bit database built on top of Carbon with a plugin for easy use in Anthracite (Carbon::Anthracite::Plugins::LimestoneClient)

A work in progress

## Carbon::SSL
An extension of Carbon that uses SSL for http connections instead of plaintext

## Carbon::CGI
An router extending Carbon::Fiber that allows routes to directories or files for CGI 1.1 execution


## etc
A work in progress, all feedback welcome
