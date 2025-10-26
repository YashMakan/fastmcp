import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'src/fastmcp_generator.dart';

Builder fastmcpBuilder(BuilderOptions options) {
  return PartBuilder([FastMcpGenerator()], '.fastmcp.g.dart');
}