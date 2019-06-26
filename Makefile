CC=gcc
OMP_FLAG=-fopenmp
MATH_FLAG=-lm

all: otsu_segmentation canny_detection cluster_segmentation

otsu_segmentation: otsu_segmentation.c bmp_image_util.h
	$(CC) $(OMP_FLAG) $(MATH_FLAG) otsu_segmentation.c -o otsu_segmentation.exe
	echo Successfully built the otsu segmentation application!!!

canny_detection: canny_edge_detection.c bmp_image_util.h
	$(CC) $(OMP_FLAG) $(MATH_FLAG) canny_edge_detection.c -o canny_edge_detection.exe
	echo Successfully built the canny edge detection application!!!

cluster_segmentation: cluster_segmentation.c bmp_image_util.h
	$(CC) $(OMP_FLAG) $(MATH_FLAG) cluster_segmentation.c -o cluster_segmentation.exe
	echo Successfully built the cluster segmentation application!!!

clean:
	rm -Force otsu_segmentation.exe canny_edge_detection.exe cluster_segmentation.exe
	