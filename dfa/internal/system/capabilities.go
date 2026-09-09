package system

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// nvidiaLspciPattern mirrors fn-lib.sh's has_nvidia_hardware grep: an NVIDIA
// VGA/3D/Display controller line from `lspci -nn`.
var nvidiaLspciPattern = regexp.MustCompile(`(?i)nvidia.*(vga|3d|display)|(vga|3d|display).*nvidia`)

// nvidiaPCIVendorID is the PCI vendor id for NVIDIA, as read from
// /sys/bus/pci/devices/*/vendor.
const nvidiaPCIVendorID = "0x10de"

// containsNVIDIAController reports whether `lspci -nn` output names an
// NVIDIA VGA/3D/Display controller. Split out from HasNVIDIAHardware so the
// parsing logic is unit-testable without touching the real machine.
func containsNVIDIAController(lspciOutput string) bool {
	return nvidiaLspciPattern.MatchString(lspciOutput)
}

// HasNVIDIAHardware reports whether an NVIDIA GPU is visible on this
// machine's PCI bus. This is a thin I/O wrapper (not unit tested directly,
// per the Catalog Engine's testing decision) mirroring fn-lib.sh's
// has_nvidia_hardware: prefer `lspci`, falling back to scanning sysfs PCI
// vendor ids when lspci isn't on PATH.
func HasNVIDIAHardware() bool {
	if result, err := Run("lspci", "-nn"); err == nil && result.ExitCode == 0 {
		return containsNVIDIAController(result.Stdout)
	}

	matches, _ := filepath.Glob("/sys/bus/pci/devices/*/vendor")
	for _, path := range matches {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if strings.TrimSpace(string(data)) == nvidiaPCIVendorID {
			return true
		}
	}
	return false
}
