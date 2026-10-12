#+build windows
package platform

@(export, link_name="NvOptimusEnablement")
NvOptimusEnablement: u32 = 0

@(export, link_name="AmdPowerXpressRequestHighPerformance")
AmdPowerXpressRequestHighPerformance: i32 = 0

prefer_nvd_gpu :: proc(prefer := true) {
    NvOptimusEnablement = 1 if prefer else 0
    AmdPowerXpressRequestHighPerformance = 1 if prefer else 0
}
