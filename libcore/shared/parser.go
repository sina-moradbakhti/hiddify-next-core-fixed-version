package shared

import (
	_ "embed"
	"fmt"
	"os"

	"github.com/hiddify/ray2sing/ray2sing"
	"github.com/sagernet/sing-box/experimental/libbox"
	"github.com/sagernet/sing-box/option"
	"github.com/xmdhs/clash2singbox/convert"
	"github.com/xmdhs/clash2singbox/model/clash"
	"gopkg.in/yaml.v3"
)

//go:embed config.json.template
var configByte []byte

var configParsers = []func([]byte, bool) ([]byte, error){
	parseSingboxConfig,
	parseV2rayConfig,
	parseClashConfig,
}

func ParseConfig(path string, tempPath string, debug bool) error {
	content, err := os.ReadFile(tempPath)
	if err != nil {
		return err
	}

	var parseError error
	for index, parser := range configParsers {
		config, err := parser(content, debug)
		if err == nil {
			fmt.Printf("[ConfigParser] success with parser #%d, checking...\n", index)
			err = libbox.CheckConfig(string(config))
			if err != nil {
				return err
			}
			err = os.WriteFile(path, config, 0777)
			return err
		}
		parseError = err
	}
	return parseError
}

func parseV2rayConfig(content []byte, debug bool) ([]byte, error) {
	config, err := ray2sing.Ray2Singbox(string(content))
	if err != nil {
		fmt.Printf("[V2rayParser] error: %s\n", err)
		return nil, err
	}
	return []byte(config), nil
}

func parseClashConfig(content []byte, debug bool) ([]byte, error) {
	clashConfig := clash.Clash{}
	err := yaml.Unmarshal(content, &clashConfig)
	if err != nil {
		fmt.Printf("[ClashParser] unmarshal error: %s\n", err)
		return nil, err
	}

	sbConfig, err := convert.Clash2sing(clashConfig)
	if err != nil {
		fmt.Printf("[ClashParser] convert error: %s\n", err)
		return nil, err
	}

	output := configByte
	output, err = convert.Patch(output, sbConfig, "", "", nil)
	if err != nil {
		fmt.Printf("[ClashParser] patch error: %s\n", err)
		return nil, err
	}
	return output, nil
}

func parseSingboxConfig(content []byte, debug bool) ([]byte, error) {
	var options option.Options
	err := options.UnmarshalJSON(content)
	if err != nil {
		fmt.Printf("[SingboxParser] unmarshal error: %s\n", err)
		return nil, err
	}
	return content, nil
}
