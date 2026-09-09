package system

import "testing"

func TestContainsNVIDIAController(t *testing.T) {
	tests := []struct {
		name   string
		output string
		want   bool
	}{
		{
			name:   "nvidia VGA controller",
			output: "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117M [GeForce GTX 1650 Mobile] [10de:1f91]",
			want:   true,
		},
		{
			name:   "nvidia 3D controller",
			output: "01:00.0 3D controller [0302]: NVIDIA Corporation GA104M [GeForce RTX 3070 Mobile / Max-Q] [10de:249d]",
			want:   true,
		},
		{
			name:   "intel-only machine",
			output: "00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] [8086:9a49]",
			want:   false,
		},
		{
			name:   "empty output",
			output: "",
			want:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := containsNVIDIAController(tt.output); got != tt.want {
				t.Errorf("containsNVIDIAController(%q) = %v, want %v", tt.output, got, tt.want)
			}
		})
	}
}
