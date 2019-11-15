# zig-bare-metal-microbit

Displays "Z" on the leds

The goal is to replace the [ble buttons broadcaster](https://github.com/markfirmware/microbit-samples/blob/master/source/examples/blebuttonsbroadcaster/main.cpp) with zig on bare metal. This broadcaster is processed by [ultibo-ble-observer](https://github.com/markfirmware/ultibo-ble-observer/releases). Although it has no encryption, no privacy and no authentication, it is still useful for controlling a model railroad in a home or club setting, or at a demo.

* [microbit](https://tech.microbit.org/)
    * [runtime - not used in this bare-metal project](https://lancaster-university.github.io/microbit-docs/#)
        * [led matrix display driver](https://github.com/lancaster-university/microbit-dal/blob/master/source/drivers/MicroBitDisplay.cpp)
    * [nrf51822](https://infocenter.nordicsemi.com/pdf/nRF51822_PS_v3.1.pdf)
    * [reference](https://infocenter.nordicsemi.com/pdf/nRF51_RM_v3.0.pdf)
        * gpio p56
        * radio p81
    * [arm cortex-m0](https://developer.arm.com/ip-products/processors/cortex-m/cortex-m0)
    * [armv6m](https://static.docs.arm.com/ddi0419/e/DDI0419E_armv6m_arm.pdf?_ga=2.152616249.101383920.1573135559-619929151.1573135559)
    * [pin assignments (sheet 5)](https://github.com/bbcmicrobit/hardware/blob/master/SCH_BBC-Microbit_V1.3B.pdf)
