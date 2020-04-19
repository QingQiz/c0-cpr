obj_name = cpr
main_module = Main.hs
src_dir = ./Libs
src_file = $(shell echo $(src_dir)/*.hs)

.PHONY : test

$(obj_name) : $(main_module) $(src_file)
	ghc -O2 -j2 -i$(src_dir) $(main_module) -o $(obj_name)


clean:
	@rm -f ./*.hi ./*.o
	@rm -f $(src_dir)/*.hi $(src_dir)/*.o
	@rm -f $(obj_name)
