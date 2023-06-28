# 8086 Emulator
This project aims to emulate an intel 8086 chip. Following [the manual found here](https://edge.edx.org/c4x/BITSPilani/EEE231/asset/8086_family_Users_Manual_1_.pdf), this code is able to decode and execute a binary file which contains x86 instructions. The companion application "memory_viewer" is provided to be able to visually inspect the memory of the chip which can be dumped to a file upon completion of the emulation.

## How to build
This code served as my introduction to the [Jai programming language](https://github.com/BSVino/JaiPrimer/blob/master/JaiPrimer.md). To compile it, you will need the Jai compiler, which as of the time of writing is still in closed beta. But if you happen to have access to that beta, you can build both applications by using the following command: 
```shell
jai first.jai
```
