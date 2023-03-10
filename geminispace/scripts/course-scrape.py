import scrapy
import csv

class CoursesSpider(scrapy.Spider):
    name = "courses"
    start_urls = [ 'file:///home/siva/src/diamond/data/course-htmls/CS.html' ]

    def parse(self, response):
        with open('courses.csv', 'w', newline='') as csvfile:
            writer = csv.writer(csvfile)
            for course in response.xpath('//center/table'):
                code = course.xpath('tr[1]/td[1]/*/text()').get()
                title = course.xpath('tr[2]/td[1]/*/text()').get()
                desc = course.xpath('tr[3]/td[1]/text()').get()
                note = course.xpath('tr[4]/td[1]/*/text()').get()
                reqs1 = course.xpath('tr[5]/td[1]/*/text()').get()
                reqs2 = course.xpath('tr[6]/td[1]/*/text()').get()
                reqs3 = course.xpath('tr[7]/td[1]/*/text()').get()
                writer.writerow([code, title, desc, note, reqs1, reqs2, reqs3])
